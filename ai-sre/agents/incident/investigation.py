"""Investigation workflow steps for the Incident Response Agent."""

import logging
from dataclasses import dataclass
from typing import Any, Optional

logger = logging.getLogger(__name__)


@dataclass
class InvestigationStep:
    """A single step in the investigation workflow."""

    name: str
    description: str
    mcp_server: str
    tools: list[str]
    queries: list[dict[str, Any]]


# Pre-defined investigation steps
INVESTIGATION_STEPS: list[InvestigationStep] = [
    InvestigationStep(
        name="metrics_correlation",
        description="Query VictoriaMetrics for error rates and resource utilization",
        mcp_server="metrics-mcp",
        tools=["query_metrics", "get_error_rate", "get_latency_percentiles"],
        queries=[
            {
                "name": "error_rate_5m",
                "tool": "get_error_rate",
                "params": {"window": "5m"},
            },
            {
                "name": "error_rate_1h",
                "tool": "get_error_rate",
                "params": {"window": "1h"},
            },
            {
                "name": "latency",
                "tool": "get_latency_percentiles",
                "params": {"percentiles": [50, 95, 99]},
            },
        ],
    ),
    InvestigationStep(
        name="log_analysis",
        description="Search ClickHouse for error patterns and stack traces",
        mcp_server="metrics-mcp",
        tools=["query_logs"],
        queries=[
            {
                "name": "recent_errors",
                "tool": "query_logs",
                "params": {
                    "sql": (
                        "SELECT timestamp, level, message, pod "
                        "FROM logs "
                        "WHERE level IN ('ERROR', 'FATAL') "
                        "AND namespace = '{namespace}' "
                        "AND timestamp > now() - INTERVAL 30 MINUTE "
                        "ORDER BY timestamp DESC"
                    ),
                    "limit": 100,
                },
            },
        ],
    ),
    InvestigationStep(
        name="event_correlation",
        description="Check Kubernetes events for warnings and state changes",
        mcp_server="kubernetes-mcp",
        tools=["list_events", "list_pods"],
        queries=[
            {
                "name": "warning_events",
                "tool": "list_events",
                "params": {"field_selector": "type=Warning"},
            },
            {
                "name": "pod_status",
                "tool": "list_pods",
                "params": {},
            },
        ],
    ),
    InvestigationStep(
        name="change_correlation",
        description="Check recent deployments, commits, and ArgoCD syncs",
        mcp_server="git-mcp",
        tools=["recent_commits", "recent_prs"],
        queries=[
            {
                "name": "recent_changes",
                "tool": "recent_commits",
                "params": {"since": "4h"},
            },
        ],
    ),
    InvestigationStep(
        name="historical_patterns",
        description="Search incident history for similar past events",
        mcp_server="runbook-mcp",
        tools=["search_incidents", "suggest_runbook"],
        queries=[
            {
                "name": "similar_incidents",
                "tool": "search_incidents",
                "params": {},
            },
            {
                "name": "suggested_runbooks",
                "tool": "suggest_runbook",
                "params": {},
            },
        ],
    ),
]


class InvestigationWorkflow:
    """Manages the step-by-step investigation workflow.

    Each step uses specific MCP tools to gather signals.
    The agent (Claude Sonnet) reasons over collected signals
    to produce root cause hypotheses.
    """

    def __init__(self) -> None:
        self.steps = INVESTIGATION_STEPS
        self.results: dict[str, Any] = {}

    async def run_step(
        self,
        step_name: str,
        context: dict[str, Any],
    ) -> dict[str, Any]:
        """Execute a single investigation step.

        In production, this calls the MCP tools via the Agent SDK.
        Returns collected signals from the step.
        """
        step = next((s for s in self.steps if s.name == step_name), None)
        if not step:
            logger.warning("Unknown investigation step: %s", step_name)
            return {}

        logger.info(
            "Running investigation step: %s (%s)",
            step.name,
            step.description,
        )

        # In production, each query would be executed via MCP tools
        # Results are stored for correlation
        step_results = {
            "step": step.name,
            "description": step.description,
            "queries_executed": len(step.queries),
            "data": {},
        }

        self.results[step_name] = step_results
        return step_results

    async def run_all(self, context: dict[str, Any]) -> dict[str, Any]:
        """Execute all investigation steps in sequence."""
        all_results = {}
        for step in self.steps:
            result = await self.run_step(step.name, context)
            all_results[step.name] = result
        return all_results

    def get_signal_summary(self) -> str:
        """Summarize all collected signals for the agent's reasoning."""
        summary_parts = []
        for step_name, result in self.results.items():
            summary_parts.append(
                f"## {step_name}\n"
                f"Description: {result.get('description', '')}\n"
                f"Queries: {result.get('queries_executed', 0)}\n"
            )
        return "\n".join(summary_parts)
