"""Rate limiting and circuit breaker for AI SRE agent invocations.

Prevents runaway costs and cascading failures by limiting:
- Per-agent investigation rate
- Global Anthropic API call rate
- Daily cost cap
"""

import logging
import time
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


@dataclass
class RateLimitConfig:
    """Rate limiting configuration."""

    # Per-agent limits
    max_investigations_per_hour: int = 10

    # Global API limits
    max_api_calls_per_minute: int = 50

    # Cost cap (USD)
    max_daily_cost_usd: float = 100.0

    # Circuit breaker
    error_rate_threshold: float = 0.30
    error_rate_window_seconds: int = 300
    circuit_breaker_cooldown_seconds: int = 600


class SlidingWindowCounter:
    """Sliding window counter for rate limiting."""

    def __init__(self, window_seconds: int) -> None:
        self.window_seconds = window_seconds
        self._timestamps: list[float] = []

    def record(self) -> None:
        """Record a new event."""
        self._timestamps.append(time.time())
        self._cleanup()

    def count(self) -> int:
        """Get count of events within the window."""
        self._cleanup()
        return len(self._timestamps)

    def _cleanup(self) -> None:
        """Remove timestamps outside the window."""
        cutoff = time.time() - self.window_seconds
        while self._timestamps and self._timestamps[0] < cutoff:
            self._timestamps.pop(0)


class CircuitBreaker:
    """Circuit breaker that trips when error rate exceeds threshold.

    States:
    - CLOSED: normal operation
    - OPEN: all requests blocked, waiting for cooldown
    - HALF_OPEN: allowing one test request
    """

    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"

    def __init__(
        self,
        error_threshold: float = 0.30,
        window_seconds: int = 300,
        cooldown_seconds: int = 600,
    ) -> None:
        self.error_threshold = error_threshold
        self.window_seconds = window_seconds
        self.cooldown_seconds = cooldown_seconds
        self.state = self.CLOSED
        self._successes = SlidingWindowCounter(window_seconds)
        self._failures = SlidingWindowCounter(window_seconds)
        self._last_failure_time: float = 0.0

    def record_success(self) -> None:
        """Record a successful operation."""
        self._successes.record()
        if self.state == self.HALF_OPEN:
            self.state = self.CLOSED
            logger.info("circuit_breaker_closed")

    def record_failure(self) -> None:
        """Record a failed operation and check if breaker should trip."""
        self._failures.record()
        self._last_failure_time = time.time()
        self._check_threshold()

    def is_allowed(self) -> bool:
        """Check if a request is allowed through the circuit breaker."""
        if self.state == self.CLOSED:
            return True

        if self.state == self.OPEN:
            # Check if cooldown has elapsed
            elapsed = time.time() - self._last_failure_time
            if elapsed >= self.cooldown_seconds:
                self.state = self.HALF_OPEN
                logger.info("circuit_breaker_half_open")
                return True
            return False

        # HALF_OPEN: allow one request
        return True

    def _check_threshold(self) -> None:
        """Check if error rate exceeds threshold."""
        total = self._successes.count() + self._failures.count()
        if total < 5:
            return

        error_rate = self._failures.count() / total
        if error_rate > self.error_threshold:
            self.state = self.OPEN
            logger.warning(
                "circuit_breaker_open",
                error_rate=f"{error_rate:.2%}",
                threshold=f"{self.error_threshold:.2%}",
            )

    @property
    def error_rate(self) -> float:
        """Current error rate within the window."""
        total = self._successes.count() + self._failures.count()
        if total == 0:
            return 0.0
        return self._failures.count() / total


class AgentRateLimiter:
    """Rate limiter for the AI SRE agent system.

    Enforces per-agent, global, and cost-based limits with a circuit
    breaker for automatic shutdown on high error rates.
    """

    def __init__(self, config: RateLimitConfig | None = None) -> None:
        self.config = config or RateLimitConfig()

        # Per-agent investigation counters (role -> counter)
        self._agent_counters: dict[str, SlidingWindowCounter] = {}

        # Global API call counter
        self._api_counter = SlidingWindowCounter(60)

        # Daily cost tracking
        self._daily_cost: float = 0.0
        self._cost_reset_time: float = time.time()

        # Circuit breaker
        self.circuit_breaker = CircuitBreaker(
            error_threshold=self.config.error_rate_threshold,
            window_seconds=self.config.error_rate_window_seconds,
            cooldown_seconds=self.config.circuit_breaker_cooldown_seconds,
        )

    def check_agent_rate(self, agent_role: str) -> tuple[bool, str]:
        """Check if an agent is within its investigation rate limit."""
        if agent_role not in self._agent_counters:
            self._agent_counters[agent_role] = SlidingWindowCounter(3600)

        counter = self._agent_counters[agent_role]
        if counter.count() >= self.config.max_investigations_per_hour:
            return False, (
                f"Agent '{agent_role}' rate limit exceeded: "
                f"{counter.count()}/{self.config.max_investigations_per_hour} "
                "investigations per hour"
            )
        return True, "allowed"

    def check_api_rate(self) -> tuple[bool, str]:
        """Check global API call rate limit."""
        if self._api_counter.count() >= self.config.max_api_calls_per_minute:
            return False, (
                f"Global API rate limit exceeded: "
                f"{self._api_counter.count()}/{self.config.max_api_calls_per_minute} "
                "calls per minute"
            )
        return True, "allowed"

    def check_cost_cap(self) -> tuple[bool, str]:
        """Check daily cost cap."""
        self._maybe_reset_daily_cost()
        if self._daily_cost >= self.config.max_daily_cost_usd:
            return False, (
                f"Daily cost cap exceeded: "
                f"${self._daily_cost:.2f}/${self.config.max_daily_cost_usd:.2f}"
            )
        return True, "allowed"

    def check_circuit_breaker(self) -> tuple[bool, str]:
        """Check circuit breaker state."""
        if not self.circuit_breaker.is_allowed():
            return False, (
                f"Circuit breaker OPEN — error rate "
                f"{self.circuit_breaker.error_rate:.2%} exceeds "
                f"{self.config.error_rate_threshold:.2%} threshold"
            )
        return True, "allowed"

    def can_proceed(self, agent_role: str) -> tuple[bool, str]:
        """Run all rate limit checks for an agent invocation."""
        checks = [
            self.check_circuit_breaker,
            self.check_api_rate,
            self.check_cost_cap,
            lambda: self.check_agent_rate(agent_role),
        ]
        for check in checks:
            allowed, reason = check()
            if not allowed:
                logger.warning(
                    "rate_limit_blocked",
                    agent=agent_role,
                    reason=reason,
                )
                return False, reason
        return True, "allowed"

    def record_invocation(self, agent_role: str, cost_usd: float = 0.0) -> None:
        """Record a successful invocation for rate tracking."""
        if agent_role not in self._agent_counters:
            self._agent_counters[agent_role] = SlidingWindowCounter(3600)

        self._agent_counters[agent_role].record()
        self._api_counter.record()
        self._daily_cost += cost_usd
        self.circuit_breaker.record_success()

    def record_failure(self, agent_role: str) -> None:
        """Record a failed invocation."""
        self.circuit_breaker.record_failure()

    def _maybe_reset_daily_cost(self) -> None:
        """Reset daily cost counter if 24 hours have elapsed."""
        if time.time() - self._cost_reset_time > 86400:
            self._daily_cost = 0.0
            self._cost_reset_time = time.time()
