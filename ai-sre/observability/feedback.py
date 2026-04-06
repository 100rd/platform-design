"""Accuracy feedback tracking for AI SRE advisories.

Collects human feedback (Slack reactions) on advisory quality and
produces weekly accuracy reports to drive continuous improvement.
"""

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Optional

from .metrics import ai_sre_accuracy_ratio, ai_sre_feedback_total

logger = logging.getLogger(__name__)


@dataclass
class FeedbackEntry:
    """Single feedback entry from a human reviewer."""

    advisory_id: str
    agent_role: str
    feedback_type: str
    user_id: str
    timestamp: float = field(default_factory=time.time)


@dataclass
class AccuracyReport:
    """Weekly accuracy report for AI SRE advisories."""

    period_days: int
    total_advisories: int
    feedback_received: int
    feedback_rate: float
    root_cause_correct: int
    root_cause_wrong: int
    root_cause_accuracy: float
    helpful_count: int
    unhelpful_count: int
    helpfulness_rate: float
    by_agent: dict[str, dict[str, Any]]


class FeedbackTracker:
    """Tracks human feedback on advisory quality.

    Feedback types (mapped from Slack reactions):
    - helpful: thumbsup/+1
    - unhelpful: thumbsdown/-1
    - root_cause_correct: dart
    - root_cause_wrong: x
    """

    def __init__(self) -> None:
        self._entries: list[FeedbackEntry] = []

    def record_feedback(
        self,
        advisory_id: str,
        agent_role: str,
        feedback_type: str,
        user_id: str,
    ) -> None:
        """Record a feedback entry from a Slack reaction."""
        entry = FeedbackEntry(
            advisory_id=advisory_id,
            agent_role=agent_role,
            feedback_type=feedback_type,
            user_id=user_id,
        )
        self._entries.append(entry)

        # Update Prometheus metrics
        ai_sre_feedback_total.labels(feedback_type=feedback_type).inc()

        logger.info(
            "feedback_recorded",
            advisory_id=advisory_id,
            agent_role=agent_role,
            feedback_type=feedback_type,
        )

        # Update per-agent accuracy gauge
        self._update_accuracy_gauge(agent_role)

    def generate_report(self, period_days: int = 7) -> AccuracyReport:
        """Generate an accuracy report for the specified period."""
        cutoff = time.time() - (period_days * 86400)
        window = [e for e in self._entries if e.timestamp >= cutoff]

        # Count by type
        helpful = sum(1 for e in window if e.feedback_type == "helpful")
        unhelpful = sum(1 for e in window if e.feedback_type == "unhelpful")
        rca_correct = sum(
            1 for e in window if e.feedback_type == "root_cause_correct"
        )
        rca_wrong = sum(
            1 for e in window if e.feedback_type == "root_cause_wrong"
        )

        total_feedback = len(window)
        rca_total = rca_correct + rca_wrong

        # Per-agent breakdown
        by_agent: dict[str, dict[str, Any]] = {}
        for entry in window:
            role = entry.agent_role
            if role not in by_agent:
                by_agent[role] = {
                    "helpful": 0,
                    "unhelpful": 0,
                    "root_cause_correct": 0,
                    "root_cause_wrong": 0,
                }
            by_agent[role][entry.feedback_type] = (
                by_agent[role].get(entry.feedback_type, 0) + 1
            )

        # Calculate per-agent accuracy
        for role, counts in by_agent.items():
            role_rca = counts.get("root_cause_correct", 0) + counts.get(
                "root_cause_wrong", 0
            )
            counts["accuracy"] = (
                counts.get("root_cause_correct", 0) / role_rca
                if role_rca > 0
                else 0.0
            )

        return AccuracyReport(
            period_days=period_days,
            total_advisories=0,  # Set by caller with advisory count
            feedback_received=total_feedback,
            feedback_rate=0.0,  # Set by caller
            root_cause_correct=rca_correct,
            root_cause_wrong=rca_wrong,
            root_cause_accuracy=(
                rca_correct / rca_total if rca_total > 0 else 0.0
            ),
            helpful_count=helpful,
            unhelpful_count=unhelpful,
            helpfulness_rate=(
                helpful / (helpful + unhelpful)
                if (helpful + unhelpful) > 0
                else 0.0
            ),
            by_agent=by_agent,
        )

    def format_slack_report(self, report: AccuracyReport) -> str:
        """Format accuracy report for Slack posting."""
        lines = [
            f"*AI SRE Weekly Accuracy Report ({report.period_days}d)*",
            "",
            f"Advisories generated: {report.total_advisories}",
            f"Human feedback received: {report.feedback_received} "
            f"({report.feedback_rate:.0%} feedback rate)",
            "",
            "*Accuracy:*",
            f"  Root cause correct: {report.root_cause_correct}/"
            f"{report.root_cause_correct + report.root_cause_wrong} "
            f"({report.root_cause_accuracy:.0%})",
            f"  Recommendations helpful: {report.helpful_count}/"
            f"{report.helpful_count + report.unhelpful_count} "
            f"({report.helpfulness_rate:.0%})",
            "",
            "*By Agent:*",
        ]

        for role, counts in sorted(
            report.by_agent.items(),
            key=lambda x: x[1].get("accuracy", 0),
            reverse=True,
        ):
            accuracy = counts.get("accuracy", 0)
            lines.append(f"  {role}: {accuracy:.0%} accuracy")

        return "\n".join(lines)

    def _update_accuracy_gauge(self, agent_role: str) -> None:
        """Update Prometheus accuracy gauge for an agent role."""
        cutoff = time.time() - (7 * 86400)
        role_entries = [
            e
            for e in self._entries
            if e.agent_role == agent_role and e.timestamp >= cutoff
        ]
        correct = sum(
            1 for e in role_entries if e.feedback_type == "root_cause_correct"
        )
        wrong = sum(
            1 for e in role_entries if e.feedback_type == "root_cause_wrong"
        )
        total = correct + wrong
        if total > 0:
            ai_sre_accuracy_ratio.labels(agent_role=agent_role).set(
                correct / total
            )
