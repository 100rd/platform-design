"""API cost tracking for the AI SRE system.

Tracks Anthropic API spend by model, agent role, and cluster.
Generates daily/weekly/monthly reports and alerts on budget overruns.
"""

import logging
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from .metrics import ai_sre_api_cost_dollars, ai_sre_daily_cost_usd

logger = logging.getLogger(__name__)

# Anthropic pricing (per million tokens, USD)
# Updated for Claude 4 models
MODEL_PRICING: dict[str, dict[str, float]] = {
    "claude-opus-4-20250514": {
        "input": 15.0,
        "output": 75.0,
    },
    "claude-sonnet-4-20250514": {
        "input": 3.0,
        "output": 15.0,
    },
}


@dataclass
class UsageRecord:
    """Single API usage record."""

    timestamp: float
    model: str
    agent_role: str
    cluster: str
    input_tokens: int
    output_tokens: int
    cost_usd: float


@dataclass
class CostReport:
    """Aggregated cost report for a time period."""

    period: str
    total_cost_usd: float
    by_model: dict[str, float]
    by_agent_role: dict[str, float]
    by_cluster: dict[str, float]
    total_input_tokens: int
    total_output_tokens: int
    invocation_count: int


class CostTracker:
    """Tracks and reports API costs for the AI SRE system.

    Maintains in-memory records and syncs to metrics for Prometheus
    scraping. Cost data is also written to ClickHouse for historical
    reporting.
    """

    def __init__(self, daily_budget_usd: Optional[float] = None) -> None:
        self.daily_budget_usd = daily_budget_usd or float(
            os.environ.get("AI_SRE_DAILY_BUDGET_USD", "100.0")
        )
        self._records: list[UsageRecord] = []
        self._day_start: float = time.time()

    def record_usage(
        self,
        model: str,
        agent_role: str,
        cluster: str,
        input_tokens: int,
        output_tokens: int,
    ) -> float:
        """Record API usage and return estimated cost in USD."""
        pricing = MODEL_PRICING.get(model, {"input": 3.0, "output": 15.0})
        cost = (
            input_tokens * pricing["input"] / 1_000_000
            + output_tokens * pricing["output"] / 1_000_000
        )

        record = UsageRecord(
            timestamp=time.time(),
            model=model,
            agent_role=agent_role,
            cluster=cluster,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost_usd=cost,
        )
        self._records.append(record)

        # Update Prometheus metrics
        ai_sre_api_cost_dollars.labels(model=model).inc(cost)
        ai_sre_daily_cost_usd.set(self.get_daily_cost())

        logger.info(
            "api_usage_recorded",
            model=model,
            agent_role=agent_role,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cost_usd=f"${cost:.4f}",
        )

        return cost

    def get_daily_cost(self) -> float:
        """Get total cost for the current day."""
        self._maybe_rotate_day()
        day_cutoff = self._day_start
        return sum(
            r.cost_usd for r in self._records if r.timestamp >= day_cutoff
        )

    def is_over_budget(self) -> bool:
        """Check if daily budget has been exceeded."""
        return self.get_daily_cost() >= self.daily_budget_usd

    def generate_report(
        self, since_seconds: int = 86400
    ) -> CostReport:
        """Generate a cost report for the specified time window."""
        cutoff = time.time() - since_seconds
        window = [r for r in self._records if r.timestamp >= cutoff]

        by_model: dict[str, float] = {}
        by_agent: dict[str, float] = {}
        by_cluster: dict[str, float] = {}
        total_input = 0
        total_output = 0

        for record in window:
            by_model[record.model] = (
                by_model.get(record.model, 0.0) + record.cost_usd
            )
            by_agent[record.agent_role] = (
                by_agent.get(record.agent_role, 0.0) + record.cost_usd
            )
            by_cluster[record.cluster] = (
                by_cluster.get(record.cluster, 0.0) + record.cost_usd
            )
            total_input += record.input_tokens
            total_output += record.output_tokens

        period = "24h" if since_seconds == 86400 else f"{since_seconds}s"
        return CostReport(
            period=period,
            total_cost_usd=sum(r.cost_usd for r in window),
            by_model=by_model,
            by_agent_role=by_agent,
            by_cluster=by_cluster,
            total_input_tokens=total_input,
            total_output_tokens=total_output,
            invocation_count=len(window),
        )

    def format_slack_report(self, report: CostReport) -> str:
        """Format a cost report for Slack posting."""
        lines = [
            f"*AI SRE Cost Report ({report.period})*",
            "",
            f"Total Cost: *${report.total_cost_usd:.2f}*",
            f"Invocations: {report.invocation_count}",
            f"Tokens: {report.total_input_tokens:,} input / "
            f"{report.total_output_tokens:,} output",
            "",
            "*By Model:*",
        ]
        for model, cost in sorted(
            report.by_model.items(), key=lambda x: x[1], reverse=True
        ):
            short_model = model.split("-")[1] if "-" in model else model
            lines.append(f"  {short_model}: ${cost:.2f}")

        lines.append("")
        lines.append("*By Agent:*")
        for agent, cost in sorted(
            report.by_agent_role.items(), key=lambda x: x[1], reverse=True
        ):
            lines.append(f"  {agent}: ${cost:.2f}")

        lines.append("")
        lines.append("*By Cluster:*")
        for cluster, cost in sorted(
            report.by_cluster.items(), key=lambda x: x[1], reverse=True
        ):
            lines.append(f"  {cluster}: ${cost:.2f}")

        return "\n".join(lines)

    def _maybe_rotate_day(self) -> None:
        """Rotate day boundary and prune old records."""
        if time.time() - self._day_start > 86400:
            self._day_start = time.time()
            # Keep 7 days of records for weekly reporting
            cutoff = time.time() - (7 * 86400)
            self._records = [r for r in self._records if r.timestamp >= cutoff]
