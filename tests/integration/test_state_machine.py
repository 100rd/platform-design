"""
Integration tests for the DNS Failover Controller State Machine.

Tests cover:
- State definitions and valid transitions
- Full lifecycle: HEALTHY -> DEGRADED -> FAILING_OVER -> FAILOVER_ACTIVE -> RECOVERING -> HEALTHY
- Invalid transition rejection
- Safety checks: minimum time in state, cooldown periods, max daily failovers
- Manual authorization gate
- Registrar client interactions during failover
- Edge cases: rapid transitions, concurrent evaluations, state persistence

States (from statemachine.go):
    HEALTHY, MONITORING, DEGRADED, PREPARING, FAILING_OVER,
    FAILOVER_ACTIVE, RECOVERING, RESTORING

Safety parameters (from safety.go):
    MinTimeInState:    5 minutes
    FailoverCooldown:  1 hour
    MaxDailyFailovers: 1
    RequireManualAuth: False (True in production)
"""

import time
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, call

import pytest


# ---------------------------------------------------------------------------
# State constants (mirrors statemachine.go)
# ---------------------------------------------------------------------------

STATE_HEALTHY = "HEALTHY"
STATE_MONITORING = "MONITORING"
STATE_DEGRADED = "DEGRADED"
STATE_PREPARING = "PREPARING"
STATE_FAILING_OVER = "FAILING_OVER"
STATE_FAILOVER_ACTIVE = "FAILOVER_ACTIVE"
STATE_RECOVERING = "RECOVERING"
STATE_RESTORING = "RESTORING"

ALL_STATES = {
    STATE_HEALTHY,
    STATE_MONITORING,
    STATE_DEGRADED,
    STATE_PREPARING,
    STATE_FAILING_OVER,
    STATE_FAILOVER_ACTIVE,
    STATE_RECOVERING,
    STATE_RESTORING,
}

# Valid transitions: source -> set of allowed targets
# Based on the logical failover lifecycle in statemachine.go
VALID_TRANSITIONS = {
    STATE_HEALTHY: {STATE_MONITORING, STATE_DEGRADED},
    STATE_MONITORING: {STATE_HEALTHY, STATE_DEGRADED},
    STATE_DEGRADED: {STATE_HEALTHY, STATE_PREPARING, STATE_FAILING_OVER},
    STATE_PREPARING: {STATE_FAILING_OVER, STATE_DEGRADED, STATE_HEALTHY},
    STATE_FAILING_OVER: {STATE_FAILOVER_ACTIVE},
    STATE_FAILOVER_ACTIVE: {STATE_RECOVERING},
    STATE_RECOVERING: {STATE_RESTORING, STATE_HEALTHY},
    STATE_RESTORING: {STATE_HEALTHY, STATE_RECOVERING},
}


# ---------------------------------------------------------------------------
# Safety parameters (mirrors safety.go DefaultSafetyParams)
# ---------------------------------------------------------------------------

class SafetyParams:
    """Configuration for transition safety checks."""

    def __init__(
        self,
        min_time_in_state=timedelta(minutes=5),
        failover_cooldown=timedelta(hours=1),
        max_daily_failovers=1,
        require_manual_auth=False,
    ):
        self.min_time_in_state = min_time_in_state
        self.failover_cooldown = failover_cooldown
        self.max_daily_failovers = max_daily_failovers
        self.require_manual_auth = require_manual_auth


DEFAULT_SAFETY = SafetyParams()


# ---------------------------------------------------------------------------
# Registrar client interface (mirrors registrar.go)
# ---------------------------------------------------------------------------

class RegistrarClient:
    """Interface for domain registrar operations."""

    def get_nameservers(self, domain):
        raise NotImplementedError

    def update_nameservers(self, domain, nameservers):
        raise NotImplementedError

    def verify_propagation(self, domain, nameservers):
        raise NotImplementedError


# ---------------------------------------------------------------------------
# State Machine implementation (Python port of statemachine.go + safety.go)
# ---------------------------------------------------------------------------

class TransitionError(Exception):
    """Raised when a state transition is invalid or blocked by safety."""
    pass


class StateMachine:
    """
    DNS Failover Controller State Machine.

    Manages state transitions with safety guards, mirrors the Go implementation
    in statemachine.go and safety.go.
    """

    def __init__(self, registrar, safety_params=None, initial_time=None):
        self.registrar = registrar
        self.safety = safety_params or DEFAULT_SAFETY

        self._current_state = STATE_HEALTHY
        self._state_entered_at = initial_time or datetime.now(timezone.utc)
        self._transition_history = []
        self._failover_timestamps = []  # tracks daily failovers
        self._manual_auth_granted = False

    @property
    def current_state(self):
        return self._current_state

    @property
    def state_entered_at(self):
        return self._state_entered_at

    @property
    def transition_history(self):
        return list(self._transition_history)

    def grant_manual_authorization(self):
        """Operator grants manual authorization for failover."""
        self._manual_auth_granted = True

    def revoke_manual_authorization(self):
        """Revoke previously granted manual authorization."""
        self._manual_auth_granted = False

    def transition_to(self, target_state, now=None):
        """
        Attempt a state transition with full safety validation.

        Args:
            target_state: The desired next state.
            now: Optional override for current time (for testing).

        Raises:
            TransitionError: If the transition is invalid or blocked.
        """
        now = now or datetime.now(timezone.utc)

        # 1. Validate the transition is structurally allowed
        allowed = VALID_TRANSITIONS.get(self._current_state, set())
        if target_state not in allowed:
            raise TransitionError(
                f"Invalid transition: {self._current_state} -> {target_state}. "
                f"Allowed targets: {allowed}"
            )

        # 2. Check minimum time in state
        time_in_state = now - self._state_entered_at
        if time_in_state < self.safety.min_time_in_state:
            remaining = self.safety.min_time_in_state - time_in_state
            raise TransitionError(
                f"Minimum time in state not met. "
                f"In {self._current_state} for {time_in_state}, "
                f"need {remaining} more."
            )

        # 3. Failover-specific safety checks
        if target_state == STATE_FAILING_OVER:
            self._validate_failover_safety(now)

        # 4. Execute the transition
        from_state = self._current_state
        self._current_state = target_state
        self._state_entered_at = now
        self._transition_history.append({
            "from": from_state,
            "to": target_state,
            "timestamp": now,
        })

        # 5. Track failover timestamps
        if target_state == STATE_FAILING_OVER:
            self._failover_timestamps.append(now)
            self._manual_auth_granted = False  # consume the authorization

    def _validate_failover_safety(self, now):
        """Additional safety checks specific to entering FAILING_OVER."""
        # Check cooldown since last failover
        if self._failover_timestamps:
            last_failover = self._failover_timestamps[-1]
            since_last = now - last_failover
            if since_last < self.safety.failover_cooldown:
                remaining = self.safety.failover_cooldown - since_last
                raise TransitionError(
                    f"Failover cooldown not met. "
                    f"Last failover was {since_last} ago, "
                    f"need {remaining} more."
                )

        # Check max daily failovers
        day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        daily_count = sum(
            1 for ts in self._failover_timestamps if ts >= day_start
        )
        if daily_count >= self.safety.max_daily_failovers:
            raise TransitionError(
                f"Max daily failovers ({self.safety.max_daily_failovers}) reached. "
                f"Already had {daily_count} today."
            )

        # Check manual authorization
        if self.safety.require_manual_auth and not self._manual_auth_granted:
            raise TransitionError(
                "Manual authorization required for failover but not granted."
            )

    def evaluate(self, health_scores, now=None):
        """
        Evaluate current health and trigger transitions as needed.
        Mirrors StateMachine.Evaluate in statemachine.go.

        Args:
            health_scores: Dict of provider_name -> score (0-100).
            now: Optional time override.
        """
        now = now or datetime.now(timezone.utc)

        if self._current_state == STATE_HEALTHY:
            # If any provider drops below 40, go to DEGRADED
            for provider, score in health_scores.items():
                if score < 40:
                    try:
                        self.transition_to(STATE_DEGRADED, now)
                    except TransitionError:
                        pass  # safety prevents transition
                    return

        elif self._current_state == STATE_DEGRADED:
            # If all providers recovered, go back to HEALTHY
            all_healthy = all(s >= 60 for s in health_scores.values())
            if all_healthy:
                try:
                    self.transition_to(STATE_HEALTHY, now)
                except TransitionError:
                    pass
                return

            # If any provider is critically low, prepare failover
            for provider, score in health_scores.items():
                if score < 20:
                    try:
                        self.transition_to(STATE_FAILING_OVER, now)
                    except TransitionError:
                        pass
                    return

        elif self._current_state == STATE_FAILOVER_ACTIVE:
            # Check if recovery is possible
            all_healthy = all(s >= 80 for s in health_scores.values())
            if all_healthy:
                try:
                    self.transition_to(STATE_RECOVERING, now)
                except TransitionError:
                    pass

        elif self._current_state == STATE_RECOVERING:
            # Verify recovery is stable, return to HEALTHY
            all_healthy = all(s >= 80 for s in health_scores.values())
            if all_healthy:
                try:
                    self.transition_to(STATE_HEALTHY, now)
                except TransitionError:
                    pass

    def execute_failover(self, domain, failed_provider_ns, healthy_ns):
        """
        Execute the actual DNS failover by updating nameservers.
        Only callable when in FAILING_OVER state.
        """
        if self._current_state != STATE_FAILING_OVER:
            raise TransitionError(
                f"Cannot execute failover in state {self._current_state}"
            )

        # 1. Update nameservers to remove failed provider
        self.registrar.update_nameservers(domain, healthy_ns)

        # 2. Verify propagation
        propagated = self.registrar.verify_propagation(domain, healthy_ns)
        if not propagated:
            raise TransitionError(
                "Nameserver propagation verification failed"
            )

        # 3. Transition to FAILOVER_ACTIVE
        self.transition_to(STATE_FAILOVER_ACTIVE)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_registrar():
    """Mock registrar client with sensible defaults."""
    registrar = MagicMock(spec=RegistrarClient)
    registrar.get_nameservers.return_value = [
        "ns1.cloudflare.com",
        "ns1.route53.aws.com",
    ]
    registrar.update_nameservers.return_value = None
    registrar.verify_propagation.return_value = True
    return registrar


@pytest.fixture
def default_sm(mock_registrar):
    """State machine with default safety parameters."""
    return StateMachine(mock_registrar)


@pytest.fixture
def relaxed_safety():
    """Safety parameters with very short timers for fast tests."""
    return SafetyParams(
        min_time_in_state=timedelta(seconds=0),
        failover_cooldown=timedelta(seconds=0),
        max_daily_failovers=100,
        require_manual_auth=False,
    )


@pytest.fixture
def relaxed_sm(mock_registrar, relaxed_safety):
    """State machine with relaxed safety for testing transitions."""
    return StateMachine(mock_registrar, relaxed_safety)


@pytest.fixture
def strict_safety():
    """Safety parameters requiring manual auth."""
    return SafetyParams(
        min_time_in_state=timedelta(minutes=5),
        failover_cooldown=timedelta(hours=1),
        max_daily_failovers=1,
        require_manual_auth=True,
    )


@pytest.fixture
def strict_sm(mock_registrar, strict_safety):
    """State machine with strict production-like safety."""
    return StateMachine(mock_registrar, strict_safety)


def _advance_time(sm, minutes):
    """Return a datetime that is `minutes` after the SM entered current state."""
    return sm.state_entered_at + timedelta(minutes=minutes)


# ---------------------------------------------------------------------------
# Initial State Tests
# ---------------------------------------------------------------------------

class TestInitialState:
    """Verify the state machine starts correctly."""

    def test_starts_in_healthy(self, default_sm):
        assert default_sm.current_state == STATE_HEALTHY

    def test_initial_history_is_empty(self, default_sm):
        assert default_sm.transition_history == []

    def test_state_entered_at_is_recent(self, default_sm):
        age = datetime.now(timezone.utc) - default_sm.state_entered_at
        assert age < timedelta(seconds=5)


# ---------------------------------------------------------------------------
# Valid Transition Tests
# ---------------------------------------------------------------------------

class TestValidTransitions:
    """Test all valid transitions in the state graph."""

    def test_healthy_to_degraded(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        assert relaxed_sm.current_state == STATE_DEGRADED

    def test_healthy_to_monitoring(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_MONITORING)
        assert relaxed_sm.current_state == STATE_MONITORING

    def test_monitoring_to_healthy(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_MONITORING)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_monitoring_to_degraded(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_MONITORING)
        relaxed_sm.transition_to(STATE_DEGRADED)
        assert relaxed_sm.current_state == STATE_DEGRADED

    def test_degraded_to_healthy(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_degraded_to_failing_over(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        assert relaxed_sm.current_state == STATE_FAILING_OVER

    def test_degraded_to_preparing(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_PREPARING)
        assert relaxed_sm.current_state == STATE_PREPARING

    def test_preparing_to_failing_over(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_PREPARING)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        assert relaxed_sm.current_state == STATE_FAILING_OVER

    def test_preparing_to_healthy_abort(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_PREPARING)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_failing_over_to_failover_active(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        assert relaxed_sm.current_state == STATE_FAILOVER_ACTIVE

    def test_failover_active_to_recovering(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        assert relaxed_sm.current_state == STATE_RECOVERING

    def test_recovering_to_healthy(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_recovering_to_restoring(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        relaxed_sm.transition_to(STATE_RESTORING)
        assert relaxed_sm.current_state == STATE_RESTORING

    def test_restoring_to_healthy(self, relaxed_sm):
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        relaxed_sm.transition_to(STATE_RESTORING)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY


class TestFullLifecycle:
    """Test the complete failover and recovery lifecycle."""

    def test_full_failover_and_recovery(self, relaxed_sm):
        """Walk the happy path: HEALTHY -> ... -> HEALTHY."""
        path = [
            STATE_DEGRADED,
            STATE_FAILING_OVER,
            STATE_FAILOVER_ACTIVE,
            STATE_RECOVERING,
            STATE_HEALTHY,
        ]
        for state in path:
            relaxed_sm.transition_to(state)

        assert relaxed_sm.current_state == STATE_HEALTHY
        assert len(relaxed_sm.transition_history) == len(path)

    def test_full_lifecycle_with_preparing(self, relaxed_sm):
        """Walk the cautious path through PREPARING."""
        path = [
            STATE_DEGRADED,
            STATE_PREPARING,
            STATE_FAILING_OVER,
            STATE_FAILOVER_ACTIVE,
            STATE_RECOVERING,
            STATE_RESTORING,
            STATE_HEALTHY,
        ]
        for state in path:
            relaxed_sm.transition_to(state)

        assert relaxed_sm.current_state == STATE_HEALTHY
        assert len(relaxed_sm.transition_history) == len(path)

    def test_transition_history_records_all(self, relaxed_sm):
        """Every transition is recorded with from, to, and timestamp."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_HEALTHY)

        history = relaxed_sm.transition_history
        assert len(history) == 2
        assert history[0]["from"] == STATE_HEALTHY
        assert history[0]["to"] == STATE_DEGRADED
        assert history[1]["from"] == STATE_DEGRADED
        assert history[1]["to"] == STATE_HEALTHY
        for entry in history:
            assert "timestamp" in entry

    def test_abort_from_degraded(self, relaxed_sm):
        """System recovers from DEGRADED back to HEALTHY without failover."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_HEALTHY)
        assert relaxed_sm.current_state == STATE_HEALTHY
        assert len(relaxed_sm.transition_history) == 2


# ---------------------------------------------------------------------------
# Invalid Transition Tests
# ---------------------------------------------------------------------------

class TestInvalidTransitions:
    """Verify that disallowed transitions are rejected."""

    @pytest.mark.parametrize(
        "from_state,to_state",
        [
            (STATE_HEALTHY, STATE_FAILING_OVER),
            (STATE_HEALTHY, STATE_FAILOVER_ACTIVE),
            (STATE_HEALTHY, STATE_RECOVERING),
            (STATE_HEALTHY, STATE_RESTORING),
            (STATE_DEGRADED, STATE_FAILOVER_ACTIVE),
            (STATE_DEGRADED, STATE_RECOVERING),
            (STATE_DEGRADED, STATE_RESTORING),
            (STATE_FAILING_OVER, STATE_HEALTHY),
            (STATE_FAILING_OVER, STATE_DEGRADED),
            (STATE_FAILING_OVER, STATE_RECOVERING),
            (STATE_FAILOVER_ACTIVE, STATE_HEALTHY),
            (STATE_FAILOVER_ACTIVE, STATE_DEGRADED),
            (STATE_FAILOVER_ACTIVE, STATE_FAILING_OVER),
            (STATE_RECOVERING, STATE_DEGRADED),
            (STATE_RECOVERING, STATE_FAILING_OVER),
        ],
    )
    def test_invalid_transition_raises(self, relaxed_sm, from_state, to_state):
        """Each invalid transition must raise TransitionError."""
        # First, navigate to from_state via valid path
        path_to = self._path_to_state(from_state)
        for state in path_to:
            relaxed_sm.transition_to(state)
        assert relaxed_sm.current_state == from_state

        with pytest.raises(TransitionError, match="Invalid transition"):
            relaxed_sm.transition_to(to_state)

    def test_self_transition_rejected(self, relaxed_sm):
        """Transitioning to the same state is not allowed."""
        with pytest.raises(TransitionError):
            relaxed_sm.transition_to(STATE_HEALTHY)

    def test_transition_to_unknown_state(self, relaxed_sm):
        """Transitioning to a non-existent state is rejected."""
        with pytest.raises(TransitionError):
            relaxed_sm.transition_to("NONEXISTENT")

    @staticmethod
    def _path_to_state(target):
        """Return a minimal valid transition path from HEALTHY to target."""
        paths = {
            STATE_HEALTHY: [],
            STATE_MONITORING: [STATE_MONITORING],
            STATE_DEGRADED: [STATE_DEGRADED],
            STATE_PREPARING: [STATE_DEGRADED, STATE_PREPARING],
            STATE_FAILING_OVER: [STATE_DEGRADED, STATE_FAILING_OVER],
            STATE_FAILOVER_ACTIVE: [
                STATE_DEGRADED, STATE_FAILING_OVER, STATE_FAILOVER_ACTIVE
            ],
            STATE_RECOVERING: [
                STATE_DEGRADED, STATE_FAILING_OVER,
                STATE_FAILOVER_ACTIVE, STATE_RECOVERING,
            ],
            STATE_RESTORING: [
                STATE_DEGRADED, STATE_FAILING_OVER,
                STATE_FAILOVER_ACTIVE, STATE_RECOVERING, STATE_RESTORING,
            ],
        }
        return paths.get(target, [])


# ---------------------------------------------------------------------------
# Safety Check Tests
# ---------------------------------------------------------------------------

class TestMinTimeInState:
    """Verify minimum time in state enforcement."""

    def test_transition_blocked_before_min_time(self, default_sm):
        """Cannot transition before min_time_in_state (5 min default)."""
        # Try immediately -- should fail
        with pytest.raises(TransitionError, match="Minimum time in state"):
            default_sm.transition_to(STATE_DEGRADED)

    def test_transition_allowed_after_min_time(self, default_sm):
        """Transition succeeds after waiting min_time_in_state."""
        future = _advance_time(default_sm, 6)  # 6 minutes > 5 minute minimum
        default_sm.transition_to(STATE_DEGRADED, now=future)
        assert default_sm.current_state == STATE_DEGRADED

    def test_transition_blocked_at_exact_min_time(self, default_sm):
        """Transition at exactly min_time_in_state boundary should succeed."""
        # timedelta comparison: < means strictly less, so equal passes
        exact = _advance_time(default_sm, 5)
        default_sm.transition_to(STATE_DEGRADED, now=exact)
        assert default_sm.current_state == STATE_DEGRADED

    def test_min_time_resets_on_transition(self, mock_registrar):
        """After transitioning, min time clock resets."""
        sm = StateMachine(
            mock_registrar,
            SafetyParams(min_time_in_state=timedelta(minutes=2)),
        )
        t0 = sm.state_entered_at
        t1 = t0 + timedelta(minutes=3)

        sm.transition_to(STATE_DEGRADED, now=t1)

        # Now try to transition again immediately -- should block
        t2 = t1 + timedelta(seconds=30)
        with pytest.raises(TransitionError, match="Minimum time"):
            sm.transition_to(STATE_HEALTHY, now=t2)

        # After waiting, it should work
        t3 = t1 + timedelta(minutes=3)
        sm.transition_to(STATE_HEALTHY, now=t3)
        assert sm.current_state == STATE_HEALTHY


class TestFailoverCooldown:
    """Verify failover cooldown enforcement."""

    def test_cooldown_blocks_second_failover(self, mock_registrar):
        """Second failover within cooldown window is blocked."""
        sm = StateMachine(
            mock_registrar,
            SafetyParams(
                min_time_in_state=timedelta(seconds=0),
                failover_cooldown=timedelta(hours=1),
                max_daily_failovers=10,  # high limit so only cooldown matters
            ),
        )
        t0 = datetime.now(timezone.utc)

        # First failover succeeds
        sm.transition_to(STATE_DEGRADED, now=t0)
        sm.transition_to(STATE_FAILING_OVER, now=t0)
        sm.transition_to(STATE_FAILOVER_ACTIVE, now=t0)
        sm.transition_to(STATE_RECOVERING, now=t0)
        sm.transition_to(STATE_HEALTHY, now=t0)

        # Second failover 30 minutes later -- should be blocked
        t1 = t0 + timedelta(minutes=30)
        sm.transition_to(STATE_DEGRADED, now=t1)
        with pytest.raises(TransitionError, match="cooldown"):
            sm.transition_to(STATE_FAILING_OVER, now=t1)

    def test_cooldown_allows_after_expiry(self, mock_registrar):
        """Failover allowed after cooldown period expires."""
        sm = StateMachine(
            mock_registrar,
            SafetyParams(
                min_time_in_state=timedelta(seconds=0),
                failover_cooldown=timedelta(hours=1),
                max_daily_failovers=10,
            ),
        )
        t0 = datetime.now(timezone.utc)

        sm.transition_to(STATE_DEGRADED, now=t0)
        sm.transition_to(STATE_FAILING_OVER, now=t0)
        sm.transition_to(STATE_FAILOVER_ACTIVE, now=t0)
        sm.transition_to(STATE_RECOVERING, now=t0)
        sm.transition_to(STATE_HEALTHY, now=t0)

        # 2 hours later -- cooldown expired
        t1 = t0 + timedelta(hours=2)
        sm.transition_to(STATE_DEGRADED, now=t1)
        sm.transition_to(STATE_FAILING_OVER, now=t1)
        assert sm.current_state == STATE_FAILING_OVER


class TestMaxDailyFailovers:
    """Verify max daily failover limit."""

    def test_daily_limit_blocks_excess_failovers(self, mock_registrar):
        """More failovers than max_daily_failovers in one day are blocked."""
        # Use a fixed base time to avoid issues with hour-of-day
        t0 = datetime(2026, 1, 15, 8, 0, 0, tzinfo=timezone.utc)
        sm = StateMachine(
            mock_registrar,
            SafetyParams(
                min_time_in_state=timedelta(seconds=0),
                failover_cooldown=timedelta(seconds=0),
                max_daily_failovers=1,
            ),
            initial_time=t0,
        )

        # First failover succeeds
        sm.transition_to(STATE_DEGRADED, now=t0)
        sm.transition_to(STATE_FAILING_OVER, now=t0)
        sm.transition_to(STATE_FAILOVER_ACTIVE, now=t0)
        sm.transition_to(STATE_RECOVERING, now=t0)
        sm.transition_to(STATE_HEALTHY, now=t0)

        # Second failover same day -- blocked
        t1 = t0 + timedelta(hours=2)
        sm.transition_to(STATE_DEGRADED, now=t1)
        with pytest.raises(TransitionError, match="Max daily failovers"):
            sm.transition_to(STATE_FAILING_OVER, now=t1)

    def test_daily_limit_resets_next_day(self, mock_registrar):
        """Failover counter resets at midnight."""
        # Use a fixed base time near end of day
        t0 = datetime(2026, 1, 15, 23, 0, 0, tzinfo=timezone.utc)
        sm = StateMachine(
            mock_registrar,
            SafetyParams(
                min_time_in_state=timedelta(seconds=0),
                failover_cooldown=timedelta(seconds=0),
                max_daily_failovers=1,
            ),
            initial_time=t0,
        )

        sm.transition_to(STATE_DEGRADED, now=t0)
        sm.transition_to(STATE_FAILING_OVER, now=t0)
        sm.transition_to(STATE_FAILOVER_ACTIVE, now=t0)
        sm.transition_to(STATE_RECOVERING, now=t0)
        sm.transition_to(STATE_HEALTHY, now=t0)

        # Next day -- should be allowed
        next_day = datetime(2026, 1, 16, 1, 0, 0, tzinfo=timezone.utc)
        sm.transition_to(STATE_DEGRADED, now=next_day)
        sm.transition_to(STATE_FAILING_OVER, now=next_day)
        assert sm.current_state == STATE_FAILING_OVER


class TestManualAuthorization:
    """Verify manual authorization gate for failover."""

    def test_failover_blocked_without_auth(self, mock_registrar, strict_safety):
        """When require_manual_auth=True, failover is blocked without auth."""
        sm = StateMachine(mock_registrar, strict_safety)
        t0 = sm.state_entered_at
        t1 = t0 + timedelta(minutes=10)

        sm.transition_to(STATE_DEGRADED, now=t1)
        t2 = t1 + timedelta(minutes=10)
        with pytest.raises(TransitionError, match="Manual authorization"):
            sm.transition_to(STATE_FAILING_OVER, now=t2)

    def test_failover_allowed_with_auth(self, mock_registrar, strict_safety):
        """Failover proceeds when manual authorization is granted."""
        sm = StateMachine(mock_registrar, strict_safety)
        t0 = sm.state_entered_at
        t1 = t0 + timedelta(minutes=10)

        sm.transition_to(STATE_DEGRADED, now=t1)
        sm.grant_manual_authorization()

        t2 = t1 + timedelta(minutes=10)
        sm.transition_to(STATE_FAILING_OVER, now=t2)
        assert sm.current_state == STATE_FAILING_OVER

    def test_auth_consumed_after_failover(self, mock_registrar):
        """Manual auth is consumed (single-use) after one failover."""
        safety = SafetyParams(
            min_time_in_state=timedelta(seconds=0),
            failover_cooldown=timedelta(seconds=0),
            max_daily_failovers=10,
            require_manual_auth=True,
        )
        sm = StateMachine(mock_registrar, safety)

        sm.grant_manual_authorization()
        sm.transition_to(STATE_DEGRADED)
        sm.transition_to(STATE_FAILING_OVER)

        # Complete the cycle
        sm.transition_to(STATE_FAILOVER_ACTIVE)
        sm.transition_to(STATE_RECOVERING)
        sm.transition_to(STATE_HEALTHY)

        # Second failover without re-granting auth -- blocked
        sm.transition_to(STATE_DEGRADED)
        with pytest.raises(TransitionError, match="Manual authorization"):
            sm.transition_to(STATE_FAILING_OVER)

    def test_revoke_auth(self, mock_registrar):
        """Revoking authorization before failover blocks it."""
        safety = SafetyParams(
            min_time_in_state=timedelta(seconds=0),
            failover_cooldown=timedelta(seconds=0),
            max_daily_failovers=10,
            require_manual_auth=True,
        )
        sm = StateMachine(mock_registrar, safety)

        sm.grant_manual_authorization()
        sm.revoke_manual_authorization()

        sm.transition_to(STATE_DEGRADED)
        with pytest.raises(TransitionError, match="Manual authorization"):
            sm.transition_to(STATE_FAILING_OVER)


# ---------------------------------------------------------------------------
# Evaluate (Health-Driven) Tests
# ---------------------------------------------------------------------------

class TestEvaluate:
    """Test the health-score-driven evaluation logic."""

    def test_healthy_stays_healthy_with_good_scores(self, relaxed_sm):
        """No transition when all providers are healthy."""
        relaxed_sm.evaluate({"cloudflare": 95, "route53": 90})
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_healthy_to_degraded_on_low_score(self, relaxed_sm):
        """Provider score below 40 triggers DEGRADED."""
        relaxed_sm.evaluate({"cloudflare": 30, "route53": 90})
        assert relaxed_sm.current_state == STATE_DEGRADED

    def test_degraded_back_to_healthy_on_recovery(self, relaxed_sm):
        """All scores above 60 triggers return to HEALTHY."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.evaluate({"cloudflare": 80, "route53": 90})
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_degraded_to_failing_over_on_critical(self, relaxed_sm):
        """Score below 20 triggers FAILING_OVER from DEGRADED."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.evaluate({"cloudflare": 10, "route53": 90})
        assert relaxed_sm.current_state == STATE_FAILING_OVER

    def test_failover_active_to_recovering_on_full_health(self, relaxed_sm):
        """All scores above 80 from FAILOVER_ACTIVE triggers RECOVERING."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.evaluate({"cloudflare": 95, "route53": 95})
        assert relaxed_sm.current_state == STATE_RECOVERING

    def test_recovering_to_healthy(self, relaxed_sm):
        """Stable healthy scores from RECOVERING returns to HEALTHY."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        relaxed_sm.evaluate({"cloudflare": 95, "route53": 95})
        assert relaxed_sm.current_state == STATE_HEALTHY

    def test_evaluate_respects_safety(self, default_sm):
        """Evaluate does not force transitions that violate safety."""
        # default_sm has 5 minute min_time_in_state, so immediate transition
        # should be caught and silently skipped
        default_sm.evaluate({"cloudflare": 10, "route53": 90})
        # Safety prevents transition, so we stay in HEALTHY
        assert default_sm.current_state == STATE_HEALTHY

    def test_degraded_stays_degraded_with_moderate_scores(self, relaxed_sm):
        """Scores between 20 and 60 keep system in DEGRADED."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.evaluate({"cloudflare": 45, "route53": 50})
        assert relaxed_sm.current_state == STATE_DEGRADED


# ---------------------------------------------------------------------------
# Registrar Integration Tests
# ---------------------------------------------------------------------------

class TestRegistrarIntegration:
    """Test interactions between state machine and registrar client."""

    def test_execute_failover_calls_registrar(self, relaxed_sm, mock_registrar):
        """Failover execution updates nameservers and verifies propagation."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)

        relaxed_sm.execute_failover(
            domain="example.com",
            failed_provider_ns=["ns1.route53.aws.com"],
            healthy_ns=["ns1.cloudflare.com", "ns2.cloudflare.com"],
        )

        mock_registrar.update_nameservers.assert_called_once_with(
            "example.com",
            ["ns1.cloudflare.com", "ns2.cloudflare.com"],
        )
        mock_registrar.verify_propagation.assert_called_once_with(
            "example.com",
            ["ns1.cloudflare.com", "ns2.cloudflare.com"],
        )
        assert relaxed_sm.current_state == STATE_FAILOVER_ACTIVE

    def test_execute_failover_fails_on_propagation(
        self, relaxed_sm, mock_registrar
    ):
        """If propagation verification fails, failover raises and stays in FAILING_OVER."""
        mock_registrar.verify_propagation.return_value = False

        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)

        with pytest.raises(TransitionError, match="propagation"):
            relaxed_sm.execute_failover(
                domain="example.com",
                failed_provider_ns=["ns1.route53.aws.com"],
                healthy_ns=["ns1.cloudflare.com"],
            )
        # Should remain in FAILING_OVER since transition to ACTIVE was not reached
        assert relaxed_sm.current_state == STATE_FAILING_OVER

    def test_execute_failover_wrong_state(self, relaxed_sm):
        """Cannot execute failover when not in FAILING_OVER state."""
        with pytest.raises(TransitionError, match="Cannot execute failover"):
            relaxed_sm.execute_failover(
                domain="example.com",
                failed_provider_ns=[],
                healthy_ns=["ns1.cloudflare.com"],
            )

    def test_registrar_called_in_correct_order(self, relaxed_sm, mock_registrar):
        """update_nameservers is called before verify_propagation."""
        call_order = []
        mock_registrar.update_nameservers.side_effect = (
            lambda *a: call_order.append("update")
        )
        mock_registrar.verify_propagation.side_effect = (
            lambda *a: (call_order.append("verify"), True)[-1]
        )

        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        relaxed_sm.execute_failover("example.com", [], ["ns1.cf.com"])

        assert call_order == ["update", "verify"]


# ---------------------------------------------------------------------------
# Edge Cases
# ---------------------------------------------------------------------------

class TestEdgeCases:
    """Edge cases and stress scenarios."""

    def test_rapid_transitions_with_relaxed_safety(self, relaxed_sm):
        """Rapid valid transitions should all succeed."""
        states = [
            STATE_DEGRADED,
            STATE_FAILING_OVER,
            STATE_FAILOVER_ACTIVE,
            STATE_RECOVERING,
            STATE_HEALTHY,
            STATE_DEGRADED,
            STATE_HEALTHY,
        ]
        for state in states:
            relaxed_sm.transition_to(state)
        assert relaxed_sm.current_state == STATE_HEALTHY
        assert len(relaxed_sm.transition_history) == len(states)

    def test_state_does_not_change_on_failed_transition(self, default_sm):
        """Failed transition leaves state unchanged."""
        original = default_sm.current_state
        with pytest.raises(TransitionError):
            default_sm.transition_to(STATE_FAILING_OVER)  # invalid from HEALTHY
        assert default_sm.current_state == original

    def test_history_not_recorded_on_failed_transition(self, default_sm):
        """Failed transitions do not appear in history."""
        with pytest.raises(TransitionError):
            default_sm.transition_to(STATE_FAILING_OVER)
        assert len(default_sm.transition_history) == 0

    def test_all_states_defined_in_valid_transitions(self):
        """Every state should appear as a key in VALID_TRANSITIONS."""
        for state in ALL_STATES:
            assert state in VALID_TRANSITIONS, (
                f"State {state} has no entry in VALID_TRANSITIONS"
            )

    def test_no_state_transitions_to_itself(self):
        """No state should list itself as a valid target."""
        for state, targets in VALID_TRANSITIONS.items():
            assert state not in targets, (
                f"State {state} lists itself as valid target"
            )

    def test_multiple_full_cycles(self, mock_registrar):
        """Multiple complete failover cycles work end-to-end."""
        sm = StateMachine(
            mock_registrar,
            SafetyParams(
                min_time_in_state=timedelta(seconds=0),
                failover_cooldown=timedelta(seconds=0),
                max_daily_failovers=100,
            ),
        )
        for cycle in range(3):
            sm.transition_to(STATE_DEGRADED)
            sm.transition_to(STATE_FAILING_OVER)
            sm.transition_to(STATE_FAILOVER_ACTIVE)
            sm.transition_to(STATE_RECOVERING)
            sm.transition_to(STATE_HEALTHY)

        assert sm.current_state == STATE_HEALTHY
        assert len(sm.transition_history) == 15  # 5 transitions * 3 cycles

    def test_failover_timestamps_tracked(self, relaxed_sm):
        """Each failover adds to the timestamps list."""
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        assert len(relaxed_sm._failover_timestamps) == 1

        relaxed_sm.transition_to(STATE_FAILOVER_ACTIVE)
        relaxed_sm.transition_to(STATE_RECOVERING)
        relaxed_sm.transition_to(STATE_HEALTHY)
        relaxed_sm.transition_to(STATE_DEGRADED)
        relaxed_sm.transition_to(STATE_FAILING_OVER)
        assert len(relaxed_sm._failover_timestamps) == 2

    def test_empty_health_scores_no_crash(self, relaxed_sm):
        """Evaluate with empty health scores does not crash."""
        relaxed_sm.evaluate({})
        assert relaxed_sm.current_state == STATE_HEALTHY
