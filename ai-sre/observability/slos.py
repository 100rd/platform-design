"""SLO definitions and error budget tracking for the AI SRE system itself.

Defines availability, latency, and accuracy SLOs and calculates
remaining error budget based on recent performance data.
"""

import logging
import time
from dataclasses import dataclass, field
from typing import Any

logger = logging.getLogger(__name__)


@dataclass
class SLODefinition:
    """Definition of a Service Level Objective."""

    name: str
    description: str
    target: float
    window_seconds: int = 2592000  # 30 days
    unit: str = ""


@dataclass
class SLOStatus:
    """Current status of an SLO with error budget tracking."""

    slo: SLODefinition
    current_value: float
    error_budget_remaining: float
    is_burning_fast: bool = False
    burn_rate: float = 0.0


# SLO definitions for the AI SRE system
AI_SRE_SLOS: list[SLODefinition] = [
    SLODefinition(
        name="availability",
        description="AI SRE responds to > 99% of alerts within 5 minutes",
        target=0.99,
        unit="ratio",
    ),
    SLODefinition(
        name="latency_p95",
        description="Time to first advisory < 2 minutes (p95)",
        target=120.0,
        unit="seconds",
    ),
    SLODefinition(
        name="accuracy",
        description="> 80% of advisories rated helpful by humans",
        target=0.80,
        unit="ratio",
    ),
]


class SLOTracker:
    """Tracks SLO compliance and error budget for the AI SRE system."""

    def __init__(self) -> None:
        self._response_times: list[tuple[float, float]] = []
        self._alerts_total: int = 0
        self._alerts_responded: int = 0
        self._alerts_within_sla: int = 0

    def record_alert_response(
        self, response_time_seconds: float, responded: bool = True
    ) -> None:
        """Record an alert response for SLO tracking."""
        now = time.time()
        self._alerts_total += 1

        if responded:
            self._alerts_responded += 1
            self._response_times.append((now, response_time_seconds))

            if response_time_seconds <= 300:  # 5-minute SLA
                self._alerts_within_sla += 1

    def get_availability(self) -> float:
        """Calculate current availability ratio."""
        if self._alerts_total == 0:
            return 1.0
        return self._alerts_within_sla / self._alerts_total

    def get_latency_p95(self) -> float:
        """Calculate p95 response time in seconds."""
        if not self._response_times:
            return 0.0

        # Get response times within the SLO window (30 days)
        cutoff = time.time() - 2592000
        recent = [
            rt for ts, rt in self._response_times if ts >= cutoff
        ]

        if not recent:
            return 0.0

        recent.sort()
        idx = int(len(recent) * 0.95)
        return recent[min(idx, len(recent) - 1)]

    def get_status(self) -> list[SLOStatus]:
        """Get current status for all SLOs."""
        statuses = []

        # Availability SLO
        availability = self.get_availability()
        avail_slo = AI_SRE_SLOS[0]
        avail_budget = max(0, (availability - avail_slo.target) / (1 - avail_slo.target))
        statuses.append(
            SLOStatus(
                slo=avail_slo,
                current_value=availability,
                error_budget_remaining=avail_budget,
                is_burning_fast=avail_budget < 0.25,
            )
        )

        # Latency SLO
        latency = self.get_latency_p95()
        latency_slo = AI_SRE_SLOS[1]
        latency_budget = max(
            0, (latency_slo.target - latency) / latency_slo.target
        ) if latency > 0 else 1.0
        statuses.append(
            SLOStatus(
                slo=latency_slo,
                current_value=latency,
                error_budget_remaining=latency_budget,
                is_burning_fast=latency_budget < 0.25,
            )
        )

        return statuses

    def format_slack_report(self) -> str:
        """Format SLO status for Slack posting."""
        statuses = self.get_status()
        lines = ["*AI SRE System SLOs*", ""]

        for status in statuses:
            emoji = ":large_green_circle:" if not status.is_burning_fast else ":red_circle:"
            budget_pct = f"{status.error_budget_remaining:.0%}"
            lines.append(
                f"{emoji} *{status.slo.name}*: "
                f"{status.current_value:.2f} (target: {status.slo.target}) "
                f"| Budget: {budget_pct}"
            )
            lines.append(f"    _{status.slo.description}_")

        return "\n".join(lines)
