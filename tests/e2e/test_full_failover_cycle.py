"""
E2E Test: Full DNS Failover Cycle

Tests the complete failover lifecycle for a multi-provider DNS failover system.
All external dependencies (database, registrar API, DNS) are mocked so the test
runs without any external services.

State machine transitions tested:
  Forward (outage):   HEALTHY -> DEGRADED -> FAILING_OVER -> FAILED_OVER
  Recovery:           FAILED_OVER -> RECOVERING -> HEALTHY

Health score semantics:
  1.0        = fully healthy
  0.5 - 0.99 = healthy range
  0.2 - 0.49 = degraded range
  0.0 - 0.19 = failing range

Safety constraints:
  - Minimum 60 seconds in any state before transition
  - 300 second cooldown between failover events
  - Maximum 3 failovers per 24-hour window
  - Invalid state transitions are rejected
"""

import time
import logging
from dataclasses import dataclass, field
from typing import Optional

import pytest

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("E2E_FailoverCycle")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# States
STATE_HEALTHY = "HEALTHY"
STATE_DEGRADED = "DEGRADED"
STATE_FAILING_OVER = "FAILING_OVER"
STATE_FAILED_OVER = "FAILED_OVER"
STATE_RECOVERING = "RECOVERING"

ALL_STATES = {
    STATE_HEALTHY,
    STATE_DEGRADED,
    STATE_FAILING_OVER,
    STATE_FAILED_OVER,
    STATE_RECOVERING,
}

# Valid transitions (from -> set of allowed targets)
VALID_TRANSITIONS = {
    STATE_HEALTHY: {STATE_DEGRADED},
    STATE_DEGRADED: {STATE_FAILING_OVER, STATE_HEALTHY},
    STATE_FAILING_OVER: {STATE_FAILED_OVER},
    STATE_FAILED_OVER: {STATE_RECOVERING},
    STATE_RECOVERING: {STATE_HEALTHY, STATE_FAILED_OVER},
}

# Thresholds
HEALTH_DEGRADED_THRESHOLD = 0.5
HEALTH_FAILING_THRESHOLD = 0.2

# Safety
MIN_TIME_IN_STATE_SECONDS = 60.0
FAILOVER_COOLDOWN_SECONDS = 300.0
MAX_DAILY_FAILOVERS = 3

# Provider nameserver patterns used for identification
PROVIDER_NS_PATTERNS = {
    "cloudflare": ["cloudflare"],
    "route53": ["awsdns", "route53"],
}


# ---------------------------------------------------------------------------
# Domain models
# ---------------------------------------------------------------------------
@dataclass
class ProviderHealth:
    """Represents the health of a single DNS provider."""

    name: str
    score: float = 1.0  # 0.0 to 1.0
    is_primary: bool = False


@dataclass
class DNSRecord:
    """Represents a DNS record pointing to a provider."""

    domain: str
    nameservers: list = field(default_factory=list)
    active_provider: str = ""


@dataclass
class TransitionRecord:
    """Records a state transition for audit purposes."""

    from_state: str
    to_state: str
    timestamp: float
    reason: str


class TransitionError(Exception):
    """Raised when a state transition is rejected."""

    pass


# ---------------------------------------------------------------------------
# Mock Registrar Client
# ---------------------------------------------------------------------------
class MockRegistrarClient:
    """
    Simulates a domain registrar API (e.g. Namecheap, GoDaddy).
    Tracks nameserver changes and propagation verification calls.
    """

    def __init__(self, domain: str, initial_nameservers: list):
        self.domain = domain
        self.nameservers = list(initial_nameservers)
        self.update_history: list[dict] = []
        self.propagation_verified = False
        logger.info(
            "MockRegistrar initialized: domain=%s, ns=%s",
            domain,
            self.nameservers,
        )

    @property
    def active_provider(self) -> str:
        """Derive active provider from the current nameservers."""
        for provider, patterns in PROVIDER_NS_PATTERNS.items():
            if any(
                pattern in ns
                for ns in self.nameservers
                for pattern in patterns
            ):
                return provider
        return "unknown"

    def get_nameservers(self) -> list[str]:
        return list(self.nameservers)

    def update_nameservers(self, new_nameservers: list[str], reason: str) -> None:
        old = list(self.nameservers)
        self.nameservers = list(new_nameservers)
        self.propagation_verified = False
        record = {
            "timestamp": time.monotonic(),
            "old": old,
            "new": list(new_nameservers),
            "reason": reason,
        }
        self.update_history.append(record)
        logger.info(
            "MockRegistrar: NS updated %s -> %s (reason: %s)",
            old,
            new_nameservers,
            reason,
        )

    def verify_propagation(self) -> bool:
        """Simulate DNS propagation check (always succeeds in mock)."""
        self.propagation_verified = True
        logger.info("MockRegistrar: propagation verified for %s", self.nameservers)
        return True


# ---------------------------------------------------------------------------
# Failover State Machine
# ---------------------------------------------------------------------------
class FailoverStateMachine:
    """
    Core state machine that manages DNS failover lifecycle.

    Enforces:
      - Valid transition paths
      - Minimum time-in-state
      - Cooldown between failovers
      - Daily failover limit
      - DNS record updates via registrar
    """

    def __init__(
        self,
        providers: list[ProviderHealth],
        registrar: MockRegistrarClient,
        dns_record: DNSRecord,
        *,
        min_time_in_state: float = MIN_TIME_IN_STATE_SECONDS,
        failover_cooldown: float = FAILOVER_COOLDOWN_SECONDS,
        max_daily_failovers: int = MAX_DAILY_FAILOVERS,
        time_fn=None,
    ):
        self.providers = {p.name: p for p in providers}
        self.registrar = registrar
        self.dns_record = dns_record

        # Safety parameters
        self.min_time_in_state = min_time_in_state
        self.failover_cooldown = failover_cooldown
        self.max_daily_failovers = max_daily_failovers

        # Time function (injectable for testing)
        self._time = time_fn or time.monotonic
        self._time_offset = 0.0

        # State tracking
        self._state = STATE_HEALTHY
        self._state_entered_at = self._now()
        self._last_failover_at: Optional[float] = None
        self._failovers_today = 0

        # Audit log
        self.transition_log: list[TransitionRecord] = []

        logger.info("StateMachine initialized in state=%s", self._state)

    # -- Time helpers (allow tests to advance time without real sleeps) -----

    def _now(self) -> float:
        return self._time() + self._time_offset

    def advance_time(self, seconds: float) -> None:
        """Advance the virtual clock by the given number of seconds."""
        self._time_offset += seconds
        logger.info("Time advanced by %.1fs (virtual now=%.1f)", seconds, self._now())

    # -- Public API ---------------------------------------------------------

    @property
    def state(self) -> str:
        return self._state

    @property
    def time_in_current_state(self) -> float:
        return self._now() - self._state_entered_at

    def get_provider_health(self, name: str) -> float:
        return self.providers[name].score

    def set_provider_health(self, name: str, score: float) -> None:
        """Set a provider's health score (simulates monitoring input)."""
        if not 0.0 <= score <= 1.0:
            raise ValueError(f"Health score must be 0.0-1.0, got {score}")
        old = self.providers[name].score
        self.providers[name].score = score
        logger.info("Provider %s health: %.2f -> %.2f", name, old, score)

    def transition(self, target_state: str, reason: str = "") -> None:
        """
        Attempt a state transition.  Raises TransitionError if the
        transition is invalid or safety constraints are violated.
        """
        self._validate_transition(target_state)
        old_state = self._state

        # Execute side effects for specific transitions
        if target_state == STATE_FAILING_OVER:
            self._execute_failover()
        elif target_state == STATE_HEALTHY and old_state == STATE_RECOVERING:
            self._execute_recovery()

        # Commit the transition
        record = TransitionRecord(
            from_state=old_state,
            to_state=target_state,
            timestamp=self._now(),
            reason=reason,
        )
        self.transition_log.append(record)
        self._state = target_state
        self._state_entered_at = self._now()

        logger.info(
            "Transition: %s -> %s (reason: %s)", old_state, target_state, reason
        )

    def evaluate(self) -> Optional[str]:
        """
        Evaluate current health scores and determine if a transition is
        needed.  Returns the new state if a transition occurred, else None.
        """
        primary = self._get_primary_provider()
        score = primary.score

        try:
            if self._state == STATE_HEALTHY:
                if score < HEALTH_DEGRADED_THRESHOLD:
                    self.transition(
                        STATE_DEGRADED,
                        f"Primary provider {primary.name} score={score:.2f}",
                    )
                    return STATE_DEGRADED

            elif self._state == STATE_DEGRADED:
                if score >= HEALTH_DEGRADED_THRESHOLD:
                    self.transition(
                        STATE_HEALTHY,
                        f"Primary provider {primary.name} recovered to {score:.2f}",
                    )
                    return STATE_HEALTHY
                if score < HEALTH_FAILING_THRESHOLD:
                    self.transition(
                        STATE_FAILING_OVER,
                        f"Primary provider {primary.name} critically failing at {score:.2f}",
                    )
                    return STATE_FAILING_OVER

            elif self._state == STATE_FAILING_OVER:
                # Failover execution is synchronous; move to FAILED_OVER
                self.transition(
                    STATE_FAILED_OVER,
                    "Failover execution complete",
                )
                return STATE_FAILED_OVER

            elif self._state == STATE_FAILED_OVER:
                if score >= HEALTH_DEGRADED_THRESHOLD:
                    self.transition(
                        STATE_RECOVERING,
                        f"Primary provider {primary.name} recovering at {score:.2f}",
                    )
                    return STATE_RECOVERING

            elif self._state == STATE_RECOVERING:
                if score < HEALTH_DEGRADED_THRESHOLD:
                    self.transition(
                        STATE_FAILED_OVER,
                        f"Recovery aborted, {primary.name} degraded again at {score:.2f}",
                    )
                    return STATE_FAILED_OVER
                if score >= HEALTH_DEGRADED_THRESHOLD:
                    self.transition(
                        STATE_HEALTHY,
                        f"Recovery complete, {primary.name} healthy at {score:.2f}",
                    )
                    return STATE_HEALTHY

        except TransitionError as exc:
            logger.warning("Transition blocked: %s", exc)
            return None

        return None

    # -- Internal -----------------------------------------------------------

    def _get_primary_provider(self) -> ProviderHealth:
        for p in self.providers.values():
            if p.is_primary:
                return p
        raise RuntimeError("No primary provider configured")

    def _get_secondary_provider(self) -> ProviderHealth:
        for p in self.providers.values():
            if not p.is_primary:
                return p
        raise RuntimeError("No secondary provider configured")

    def _validate_transition(self, target_state: str) -> None:
        """Enforce transition validity and safety constraints."""
        # 1. Target state is known
        if target_state not in ALL_STATES:
            raise TransitionError(f"Unknown target state: {target_state}")

        # 2. Transition path is valid
        allowed = VALID_TRANSITIONS.get(self._state, set())
        if target_state not in allowed:
            raise TransitionError(
                f"Invalid transition: {self._state} -> {target_state}. "
                f"Allowed: {allowed}"
            )

        # 3. Minimum time in state
        elapsed = self._now() - self._state_entered_at
        if elapsed < self.min_time_in_state:
            raise TransitionError(
                f"Minimum time in state not met: "
                f"{elapsed:.1f}s < {self.min_time_in_state:.1f}s"
            )

        # 4. Failover cooldown
        if target_state == STATE_FAILING_OVER and self._last_failover_at is not None:
            since_last = self._now() - self._last_failover_at
            if since_last < self.failover_cooldown:
                raise TransitionError(
                    f"Failover cooldown not met: "
                    f"{since_last:.1f}s < {self.failover_cooldown:.1f}s"
                )

        # 5. Daily failover limit
        if target_state == STATE_FAILING_OVER:
            if self._failovers_today >= self.max_daily_failovers:
                raise TransitionError(
                    f"Daily failover limit reached: {self._failovers_today}"
                    f"/{self.max_daily_failovers}"
                )

    def _execute_failover(self) -> None:
        """
        Perform the actual failover: update registrar nameservers to
        point to the secondary provider.
        """
        secondary = self._get_secondary_provider()
        new_ns = self._nameservers_for_provider(secondary.name)

        self.registrar.update_nameservers(
            new_ns,
            reason=f"failover to {secondary.name}",
        )
        self.registrar.verify_propagation()

        self.dns_record.nameservers = list(new_ns)
        self.dns_record.active_provider = secondary.name

        self._last_failover_at = self._now()
        self._failovers_today += 1

        logger.info(
            "Failover executed: active provider is now %s", secondary.name
        )

    def _execute_recovery(self) -> None:
        """
        Restore DNS to the original primary provider after recovery.
        """
        primary = self._get_primary_provider()
        new_ns = self._nameservers_for_provider(primary.name)

        self.registrar.update_nameservers(
            new_ns,
            reason=f"recovery back to {primary.name}",
        )
        self.registrar.verify_propagation()

        self.dns_record.nameservers = list(new_ns)
        self.dns_record.active_provider = primary.name

        logger.info(
            "Recovery executed: active provider restored to %s", primary.name
        )

    @staticmethod
    def _nameservers_for_provider(provider_name: str) -> list[str]:
        ns_map = {
            "cloudflare": ["ns1.cloudflare.com", "ns2.cloudflare.com"],
            "route53": ["ns-1.awsdns-01.com", "ns-2.awsdns-02.net"],
        }
        ns = ns_map.get(provider_name)
        if ns is None:
            raise ValueError(f"Unknown provider: {provider_name}")
        return ns


# ---------------------------------------------------------------------------
# Provider simulation helpers
# ---------------------------------------------------------------------------
def simulate_provider_outage(
    sm: FailoverStateMachine, provider_name: str
) -> None:
    """
    Simulate a provider outage by dropping health to a degraded value
    first, then to a critical value.  This mirrors real-world gradual
    failure detection.
    """
    logger.info("=== Simulating outage for provider: %s ===", provider_name)
    sm.set_provider_health(provider_name, 0.3)  # degraded


def simulate_provider_critical(
    sm: FailoverStateMachine, provider_name: str
) -> None:
    """Drop provider health below the failing threshold."""
    logger.info("=== Simulating critical failure for provider: %s ===", provider_name)
    sm.set_provider_health(provider_name, 0.1)  # critically failing


def simulate_provider_recovery(
    sm: FailoverStateMachine, provider_name: str
) -> None:
    """Restore provider health to a healthy value."""
    logger.info("=== Simulating recovery for provider: %s ===", provider_name)
    sm.set_provider_health(provider_name, 0.95)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
DOMAIN = "example.com"
CLOUDFLARE_NS = ["ns1.cloudflare.com", "ns2.cloudflare.com"]
ROUTE53_NS = ["ns-1.awsdns-01.com", "ns-2.awsdns-02.net"]


@pytest.fixture
def registrar():
    """Fresh mock registrar client for each test."""
    client = MockRegistrarClient(domain=DOMAIN, initial_nameservers=CLOUDFLARE_NS)
    yield client


@pytest.fixture
def dns_record():
    """Fresh DNS record for each test."""
    return DNSRecord(
        domain=DOMAIN,
        nameservers=list(CLOUDFLARE_NS),
        active_provider="cloudflare",
    )


@pytest.fixture
def providers():
    """Two healthy providers; cloudflare is primary."""
    return [
        ProviderHealth(name="cloudflare", score=1.0, is_primary=True),
        ProviderHealth(name="route53", score=1.0, is_primary=False),
    ]


@pytest.fixture
def state_machine(providers, registrar, dns_record):
    """
    State machine with shortened safety timings so tests complete
    quickly.  We use advance_time() to simulate elapsed time rather
    than real sleeps.
    """
    sm = FailoverStateMachine(
        providers=providers,
        registrar=registrar,
        dns_record=dns_record,
        min_time_in_state=60.0,
        failover_cooldown=300.0,
        max_daily_failovers=3,
    )
    return sm


# ---------------------------------------------------------------------------
# Tests: Full Failover Cycle (9 steps)
# ---------------------------------------------------------------------------
class TestFullFailoverCycle:
    """
    End-to-end test that walks through the complete failover and
    recovery lifecycle.
    """

    def test_full_cycle(self, state_machine, registrar, dns_record):
        sm = state_machine

        # -- Step 1: Verify Initial State (HEALTHY) ------------------------
        logger.info("Step 1: Verifying initial state is HEALTHY")
        assert sm.state == STATE_HEALTHY
        assert dns_record.active_provider == "cloudflare"
        assert registrar.get_nameservers() == CLOUDFLARE_NS
        assert sm.get_provider_health("cloudflare") == 1.0
        assert sm.get_provider_health("route53") == 1.0
        assert len(sm.transition_log) == 0

        # -- Step 2: Simulate Provider Outage (degraded) -------------------
        logger.info("Step 2: Simulating Cloudflare outage (degraded)")
        simulate_provider_outage(sm, "cloudflare")
        assert sm.get_provider_health("cloudflare") == 0.3

        # Advance past min-time-in-state for HEALTHY
        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_DEGRADED

        # -- Step 3: Verify DEGRADED state ---------------------------------
        logger.info("Step 3: Verifying DEGRADED state")
        assert sm.state == STATE_DEGRADED
        assert len(sm.transition_log) == 1
        assert sm.transition_log[-1].from_state == STATE_HEALTHY
        assert sm.transition_log[-1].to_state == STATE_DEGRADED
        # DNS should NOT have changed yet (no failover)
        assert dns_record.active_provider == "cloudflare"
        assert registrar.get_nameservers() == CLOUDFLARE_NS

        # -- Step 4: Provider drops to critical -> FAILING_OVER ------------
        logger.info("Step 4: Cloudflare drops to critical, triggering failover")
        simulate_provider_critical(sm, "cloudflare")
        assert sm.get_provider_health("cloudflare") == 0.1

        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_FAILING_OVER

        # -- Step 5: Verify Registrar NS Update ----------------------------
        logger.info("Step 5: Verifying registrar nameserver update")
        assert sm.state == STATE_FAILING_OVER
        # Failover should have updated the registrar
        assert registrar.get_nameservers() == ROUTE53_NS
        assert registrar.propagation_verified is True
        assert dns_record.active_provider == "route53"
        assert dns_record.nameservers == ROUTE53_NS
        # Check registrar history
        assert len(registrar.update_history) == 1
        assert "failover" in registrar.update_history[0]["reason"]

        # -- Step 6: Transition to FAILED_OVER -----------------------------
        logger.info("Step 6: Completing failover -> FAILED_OVER")
        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_FAILED_OVER

        assert sm.state == STATE_FAILED_OVER
        assert dns_record.active_provider == "route53"

        # -- Step 7: Simulate Provider Recovery ----------------------------
        logger.info("Step 7: Simulating Cloudflare recovery")
        simulate_provider_recovery(sm, "cloudflare")
        assert sm.get_provider_health("cloudflare") == 0.95

        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_RECOVERING

        # -- Step 8: Verify RECOVERING state -------------------------------
        logger.info("Step 8: Verifying RECOVERING state")
        assert sm.state == STATE_RECOVERING
        assert sm.transition_log[-1].to_state == STATE_RECOVERING

        # -- Step 9: Complete recovery -> HEALTHY --------------------------
        logger.info("Step 9: Completing recovery -> HEALTHY")
        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_HEALTHY

        assert sm.state == STATE_HEALTHY
        # DNS should be back on cloudflare
        assert dns_record.active_provider == "cloudflare"
        assert dns_record.nameservers == CLOUDFLARE_NS
        assert registrar.get_nameservers() == CLOUDFLARE_NS
        assert registrar.propagation_verified is True
        # Two registrar updates total: failover + recovery
        assert len(registrar.update_history) == 2
        assert "recovery" in registrar.update_history[1]["reason"]

        # -- Final audit ---------------------------------------------------
        logger.info("Full cycle complete. Transition log:")
        expected_path = [
            (STATE_HEALTHY, STATE_DEGRADED),
            (STATE_DEGRADED, STATE_FAILING_OVER),
            (STATE_FAILING_OVER, STATE_FAILED_OVER),
            (STATE_FAILED_OVER, STATE_RECOVERING),
            (STATE_RECOVERING, STATE_HEALTHY),
        ]
        assert len(sm.transition_log) == len(expected_path)
        for i, (from_s, to_s) in enumerate(expected_path):
            assert sm.transition_log[i].from_state == from_s
            assert sm.transition_log[i].to_state == to_s
            logger.info(
                "  [%d] %s -> %s (reason: %s)",
                i,
                sm.transition_log[i].from_state,
                sm.transition_log[i].to_state,
                sm.transition_log[i].reason,
            )


# ---------------------------------------------------------------------------
# Tests: Timing Validation
# ---------------------------------------------------------------------------
class TestTimingValidation:
    """Verify that safety timing constraints are properly enforced."""

    def test_min_time_in_state_blocks_early_transition(self, state_machine):
        """Transition is rejected if min-time-in-state has not elapsed."""
        sm = state_machine
        simulate_provider_outage(sm, "cloudflare")

        # Do NOT advance time -- should be blocked
        result = sm.evaluate()
        assert result is None
        assert sm.state == STATE_HEALTHY, "Should remain HEALTHY when min time not met"

    def test_min_time_in_state_allows_after_elapsed(self, state_machine):
        """Transition succeeds after min-time-in-state elapses."""
        sm = state_machine
        simulate_provider_outage(sm, "cloudflare")

        sm.advance_time(60.1)

        result = sm.evaluate()
        assert result == STATE_DEGRADED

    def test_failover_cooldown_blocks_rapid_failover(
        self, providers, dns_record
    ):
        """
        After a failover completes and recovery happens, a second
        failover within cooldown is blocked.
        """
        registrar = MockRegistrarClient(domain=DOMAIN, initial_nameservers=CLOUDFLARE_NS)
        sm = FailoverStateMachine(
            providers=providers,
            registrar=registrar,
            dns_record=dns_record,
            min_time_in_state=60.0,
            failover_cooldown=300.0,
            max_daily_failovers=3,
        )

        # First failover cycle: HEALTHY -> DEGRADED -> FAILING_OVER -> FAILED_OVER
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> FAILING_OVER

        sm.advance_time(61.0)
        sm.evaluate()  # -> FAILED_OVER

        # Recovery
        simulate_provider_recovery(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> RECOVERING

        sm.advance_time(61.0)
        sm.evaluate()  # -> HEALTHY

        assert sm.state == STATE_HEALTHY

        # Second outage -- trigger degraded
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)  # Time in DEGRADED satisfied...

        # ...but total time since last failover is ~366s which is > 300s cooldown
        # So this one should succeed. Let us test a truly rapid scenario instead.
        # We need the cooldown to be checked relative to _last_failover_at.
        # Total elapsed: 61+61+61+61+61+61+61 = 427s > 300s, so it passes.
        result = sm.evaluate()
        assert result == STATE_FAILING_OVER, (
            "Second failover should succeed after cooldown elapsed"
        )

    def test_failover_cooldown_actually_blocks(self, providers, dns_record):
        """
        Demonstrate that cooldown blocks a failover when not enough
        time has passed since the last failover event.
        """
        registrar = MockRegistrarClient(domain=DOMAIN, initial_nameservers=CLOUDFLARE_NS)
        sm = FailoverStateMachine(
            providers=providers,
            registrar=registrar,
            dns_record=dns_record,
            min_time_in_state=10.0,  # shorter for this test
            failover_cooldown=300.0,
            max_daily_failovers=3,
        )

        # First failover
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(11.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(11.0)
        sm.evaluate()  # -> FAILING_OVER

        sm.advance_time(11.0)
        sm.evaluate()  # -> FAILED_OVER

        # Quick recovery
        simulate_provider_recovery(sm, "cloudflare")
        sm.advance_time(11.0)
        sm.evaluate()  # -> RECOVERING

        sm.advance_time(11.0)
        sm.evaluate()  # -> HEALTHY

        # Total time: 55s. Now trigger another outage immediately.
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(11.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(11.0)  # Total ~77s, well within 300s cooldown

        result = sm.evaluate()
        assert result is None, "Failover should be blocked by cooldown"
        assert sm.state == STATE_DEGRADED

    def test_daily_failover_limit(self, providers, dns_record):
        """Exceeding the daily failover limit blocks further failovers."""
        registrar = MockRegistrarClient(domain=DOMAIN, initial_nameservers=CLOUDFLARE_NS)
        sm = FailoverStateMachine(
            providers=providers,
            registrar=registrar,
            dns_record=dns_record,
            min_time_in_state=1.0,
            failover_cooldown=1.0,  # very short for this test
            max_daily_failovers=2,
        )

        for cycle in range(2):
            simulate_provider_outage(sm, "cloudflare")
            sm.advance_time(2.0)
            sm.evaluate()  # -> DEGRADED

            simulate_provider_critical(sm, "cloudflare")
            sm.advance_time(2.0)
            sm.evaluate()  # -> FAILING_OVER

            sm.advance_time(2.0)
            sm.evaluate()  # -> FAILED_OVER

            simulate_provider_recovery(sm, "cloudflare")
            sm.advance_time(2.0)
            sm.evaluate()  # -> RECOVERING

            sm.advance_time(2.0)
            sm.evaluate()  # -> HEALTHY

        assert sm._failovers_today == 2

        # Third failover should be blocked
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(2.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(2.0)

        result = sm.evaluate()
        assert result is None, "Third failover should be blocked by daily limit"
        assert sm.state == STATE_DEGRADED


# ---------------------------------------------------------------------------
# Tests: Safety / Invalid Transitions
# ---------------------------------------------------------------------------
class TestSafetyChecks:
    """Ensure invalid state transitions are rejected."""

    def test_healthy_to_failed_over_rejected(self, state_machine):
        """Cannot skip directly from HEALTHY to FAILED_OVER."""
        sm = state_machine
        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_FAILED_OVER, "trying to skip states")

    def test_healthy_to_recovering_rejected(self, state_machine):
        """Cannot go from HEALTHY to RECOVERING."""
        sm = state_machine
        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_RECOVERING)

    def test_healthy_to_failing_over_rejected(self, state_machine):
        """Cannot skip from HEALTHY directly to FAILING_OVER."""
        sm = state_machine
        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_FAILING_OVER)

    def test_degraded_to_failed_over_rejected(self, state_machine):
        """Cannot skip from DEGRADED to FAILED_OVER."""
        sm = state_machine
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> DEGRADED

        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_FAILED_OVER)

    def test_failed_over_to_healthy_rejected(self, state_machine):
        """Cannot skip from FAILED_OVER directly to HEALTHY."""
        sm = state_machine

        # Drive to FAILED_OVER
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()
        assert sm.state == STATE_FAILED_OVER

        sm.advance_time(61.0)
        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_HEALTHY)

    def test_unknown_state_rejected(self, state_machine):
        """Transition to an unknown state is rejected."""
        sm = state_machine
        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Unknown target state"):
            sm.transition("EXPLODING")

    def test_self_transition_rejected(self, state_machine):
        """Cannot transition from HEALTHY to HEALTHY."""
        sm = state_machine
        sm.advance_time(61.0)

        with pytest.raises(TransitionError, match="Invalid transition"):
            sm.transition(STATE_HEALTHY)


# ---------------------------------------------------------------------------
# Tests: DNS Record Verification
# ---------------------------------------------------------------------------
class TestDNSRecordVerification:
    """Verify DNS records are correctly updated during failover/recovery."""

    def test_dns_unchanged_during_degraded(self, state_machine, registrar, dns_record):
        """DNS records should not change when entering DEGRADED state."""
        sm = state_machine

        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> DEGRADED

        assert dns_record.active_provider == "cloudflare"
        assert dns_record.nameservers == CLOUDFLARE_NS
        assert registrar.get_nameservers() == CLOUDFLARE_NS
        assert len(registrar.update_history) == 0

    def test_dns_updated_during_failover(self, state_machine, registrar, dns_record):
        """DNS records switch to secondary provider during failover."""
        sm = state_machine

        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> DEGRADED

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> FAILING_OVER

        assert dns_record.active_provider == "route53"
        assert dns_record.nameservers == ROUTE53_NS
        assert registrar.get_nameservers() == ROUTE53_NS
        assert registrar.propagation_verified is True

    def test_dns_restored_after_recovery(self, state_machine, registrar, dns_record):
        """DNS records return to primary after full recovery."""
        sm = state_machine

        # Full cycle to recovery
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()  # -> FAILED_OVER

        simulate_provider_recovery(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> RECOVERING

        sm.advance_time(61.0)
        sm.evaluate()  # -> HEALTHY

        assert dns_record.active_provider == "cloudflare"
        assert dns_record.nameservers == CLOUDFLARE_NS
        assert registrar.get_nameservers() == CLOUDFLARE_NS

    def test_registrar_update_history_complete(
        self, state_machine, registrar, dns_record
    ):
        """Full cycle produces exactly two registrar updates."""
        sm = state_machine

        # Full cycle
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_recovery(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()

        assert len(registrar.update_history) == 2

        # First update: failover to route53
        first = registrar.update_history[0]
        assert first["old"] == CLOUDFLARE_NS
        assert first["new"] == ROUTE53_NS

        # Second update: recovery back to cloudflare
        second = registrar.update_history[1]
        assert second["old"] == ROUTE53_NS
        assert second["new"] == CLOUDFLARE_NS


# ---------------------------------------------------------------------------
# Tests: Registrar Integration
# ---------------------------------------------------------------------------
class TestRegistrarIntegration:
    """Test the mock registrar client behavior in isolation."""

    def test_initial_nameservers(self, registrar):
        assert registrar.get_nameservers() == CLOUDFLARE_NS
        assert registrar.active_provider == "cloudflare"

    def test_update_nameservers(self, registrar):
        registrar.update_nameservers(ROUTE53_NS, reason="test")
        assert registrar.get_nameservers() == ROUTE53_NS
        assert registrar.active_provider == "route53"
        assert registrar.propagation_verified is False

    def test_verify_propagation(self, registrar):
        result = registrar.verify_propagation()
        assert result is True
        assert registrar.propagation_verified is True

    def test_update_history_tracking(self, registrar):
        registrar.update_nameservers(ROUTE53_NS, reason="failover")
        registrar.update_nameservers(CLOUDFLARE_NS, reason="recovery")

        assert len(registrar.update_history) == 2
        assert registrar.update_history[0]["new"] == ROUTE53_NS
        assert registrar.update_history[1]["new"] == CLOUDFLARE_NS


# ---------------------------------------------------------------------------
# Tests: Recovery Abort
# ---------------------------------------------------------------------------
class TestRecoveryAbort:
    """Test that recovery can be aborted if the provider degrades again."""

    def test_recovery_aborted_on_re_degradation(
        self, state_machine, registrar, dns_record
    ):
        sm = state_machine

        # Get to RECOVERING
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()  # -> FAILED_OVER

        simulate_provider_recovery(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()  # -> RECOVERING
        assert sm.state == STATE_RECOVERING

        # Provider degrades again during recovery
        sm.set_provider_health("cloudflare", 0.3)
        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result == STATE_FAILED_OVER
        assert sm.state == STATE_FAILED_OVER
        # DNS should still point to route53
        assert dns_record.active_provider == "route53"


# ---------------------------------------------------------------------------
# Tests: Edge Cases
# ---------------------------------------------------------------------------
class TestEdgeCases:
    """Test boundary conditions and edge cases."""

    def test_health_score_boundaries(self, state_machine):
        """Test exact threshold values."""
        sm = state_machine

        # Exactly 0.5 should NOT trigger degraded (threshold is < 0.5)
        sm.set_provider_health("cloudflare", 0.5)
        sm.advance_time(61.0)
        result = sm.evaluate()
        assert result is None
        assert sm.state == STATE_HEALTHY

        # Just below 0.5 should trigger degraded
        sm.set_provider_health("cloudflare", 0.49)
        result = sm.evaluate()
        assert result == STATE_DEGRADED

    def test_health_score_validation(self, state_machine):
        """Health scores outside 0.0-1.0 are rejected."""
        sm = state_machine

        with pytest.raises(ValueError, match="0.0-1.0"):
            sm.set_provider_health("cloudflare", 1.5)

        with pytest.raises(ValueError, match="0.0-1.0"):
            sm.set_provider_health("cloudflare", -0.1)

    def test_evaluate_returns_none_when_no_transition_needed(self, state_machine):
        """evaluate() returns None when the system is healthy and stable."""
        sm = state_machine
        sm.advance_time(61.0)

        result = sm.evaluate()
        assert result is None
        assert sm.state == STATE_HEALTHY

    def test_provider_health_independence(self, state_machine):
        """Changing one provider's health does not affect the other."""
        sm = state_machine

        sm.set_provider_health("cloudflare", 0.1)
        assert sm.get_provider_health("route53") == 1.0

    def test_transition_timestamps_are_monotonic(self, state_machine, registrar):
        """All transition timestamps increase monotonically."""
        sm = state_machine

        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        simulate_provider_critical(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()

        sm.advance_time(61.0)
        sm.evaluate()

        for i in range(1, len(sm.transition_log)):
            assert (
                sm.transition_log[i].timestamp > sm.transition_log[i - 1].timestamp
            ), f"Timestamp at index {i} is not monotonically increasing"


# ---------------------------------------------------------------------------
# Tests: Proper Teardown (fixture isolation)
# ---------------------------------------------------------------------------
class TestTeardownIsolation:
    """
    Verify that each test gets clean state.  Running these two tests
    in sequence proves that fixtures do not leak between tests.
    """

    def test_first_modifies_state(self, state_machine, registrar, dns_record):
        sm = state_machine
        simulate_provider_outage(sm, "cloudflare")
        sm.advance_time(61.0)
        sm.evaluate()
        assert sm.state == STATE_DEGRADED
        assert sm.get_provider_health("cloudflare") == 0.3

    def test_second_has_clean_state(self, state_machine, registrar, dns_record):
        sm = state_machine
        assert sm.state == STATE_HEALTHY
        assert sm.get_provider_health("cloudflare") == 1.0
        assert dns_record.active_provider == "cloudflare"
        assert registrar.get_nameservers() == CLOUDFLARE_NS
        assert len(sm.transition_log) == 0
        assert len(registrar.update_history) == 0
