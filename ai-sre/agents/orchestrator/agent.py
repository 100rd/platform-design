"""SRE Orchestrator Agent — routes alerts to specialized agents and aggregates advisories."""

import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from .config import (
    AGENT_SYSTEM_PROMPTS,
    AGENT_TOOL_PERMISSIONS,
    AgentDefinition,
    AgentModel,
    AgentRole,
)

logger = logging.getLogger(__name__)


@dataclass
class Advisory:
    """Structured advisory from an agent investigation."""

    agent_role: str
    summary: str
    root_cause: Optional[str] = None
    confidence: float = 0.0
    recommended_actions: list[str] = field(default_factory=list)
    related_incidents: list[str] = field(default_factory=list)
    severity: str = "info"
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


@dataclass
class InvestigationContext:
    """Context for an ongoing investigation."""

    alert_id: str
    alert_name: str
    cluster: str
    namespace: Optional[str] = None
    labels: dict[str, str] = field(default_factory=dict)
    enrichment: dict[str, Any] = field(default_factory=dict)
    advisories: list[Advisory] = field(default_factory=list)
    status: str = "pending"
    created_at: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class SREOrchestrator:
    """Main orchestrator that routes alerts to specialized agents.

    Runs as the top-level agent using Claude Opus. Receives alerts from
    the ingestion pipeline, determines which specialized agent(s) to
    invoke, collects their advisories, and posts a consolidated
    recommendation to Slack.
    """

    def __init__(
        self,
        anthropic_api_key: Optional[str] = None,
        mcp_servers: Optional[dict[str, str]] = None,
    ):
        self.api_key = anthropic_api_key or os.environ.get("ANTHROPIC_API_KEY", "")
        self.mcp_servers = mcp_servers or {}
        self.agents: dict[AgentRole, AgentDefinition] = {}
        self.active_investigations: dict[str, InvestigationContext] = {}
        self._initialize_agents()

    def _initialize_agents(self) -> None:
        """Register all specialized agent definitions."""
        for role in AgentRole:
            model = (
                AgentModel.ORCHESTRATOR
                if role == AgentRole.ORCHESTRATOR
                else AgentModel.WORKER
            )
            self.agents[role] = AgentDefinition(
                role=role,
                model=model,
                system_prompt=AGENT_SYSTEM_PROMPTS.get(role, ""),
                tool_permissions=AGENT_TOOL_PERMISSIONS.get(role, []),
            )
        logger.info("Initialized %d agent definitions", len(self.agents))

    def route_alert(self, alert: dict[str, Any]) -> AgentRole:
        """Determine which specialized agent should handle an alert.

        Routing is based on alert labels and name patterns:
        - gpu_*, dcgm_*          -> GPU Health Agent
        - kube_pod_*, container_* -> Incident Response Agent
        - node_*, kubelet_*      -> Capacity Planning Agent
        - cilium_*, network_*    -> Incident Response Agent
        - vllm_*                 -> Predictive Scaling Agent
        - cost_*                 -> Cost Optimization Agent
        - Other                  -> On-Call Copilot Agent
        """
        alert_name = alert.get("labels", {}).get("alertname", "").lower()

        routing_rules: list[tuple[list[str], AgentRole]] = [
            (["gpu_", "dcgm_"], AgentRole.GPU_HEALTH),
            (["kube_pod_", "container_"], AgentRole.INCIDENT_RESPONSE),
            (["node_", "kubelet_"], AgentRole.CAPACITY_PLANNING),
            (["cilium_", "network_"], AgentRole.INCIDENT_RESPONSE),
            (["vllm_"], AgentRole.PREDICTIVE_SCALING),
            (["cost_"], AgentRole.COST_OPTIMIZATION),
        ]

        for prefixes, role in routing_rules:
            if any(alert_name.startswith(prefix) for prefix in prefixes):
                logger.info("Routing alert '%s' to %s", alert_name, role.value)
                return role

        logger.info("No specific route for '%s', using on-call copilot", alert_name)
        return AgentRole.ONCALL_COPILOT

    async def investigate(self, alert: dict[str, Any]) -> InvestigationContext:
        """Start an investigation for an incoming alert.

        Creates an investigation context, routes to the appropriate agent,
        and returns the context with advisory. In production, this will
        invoke the Claude Agent SDK to run the specialized agent with
        its MCP tools.
        """
        alert_id = alert.get("alert_id", "unknown")
        alert_name = alert.get("labels", {}).get("alertname", "unknown")
        cluster = alert.get("labels", {}).get("cluster", "unknown")
        namespace = alert.get("labels", {}).get("namespace")

        context = InvestigationContext(
            alert_id=alert_id,
            alert_name=alert_name,
            cluster=cluster,
            namespace=namespace,
            labels=alert.get("labels", {}),
            status="investigating",
        )

        self.active_investigations[alert_id] = context
        target_role = self.route_alert(alert)

        logger.info(
            "Starting investigation for alert '%s' on cluster '%s' "
            "with agent '%s'",
            alert_name,
            cluster,
            target_role.value,
        )

        # In production, this calls the Claude Agent SDK:
        # advisory = await self._run_agent(target_role, context)
        # context.advisories.append(advisory)

        return context

    async def aggregate_advisories(
        self, context: InvestigationContext
    ) -> dict[str, Any]:
        """Combine multiple agent advisories into a single recommendation.

        The orchestrator (Opus) synthesizes findings from one or more
        worker agents into a clear, actionable advisory for the
        on-call engineer.
        """
        if not context.advisories:
            return {
                "status": "no_findings",
                "summary": f"Investigation for {context.alert_name} "
                f"on {context.cluster} produced no findings.",
            }

        return {
            "status": "advisory_ready",
            "alert_id": context.alert_id,
            "alert_name": context.alert_name,
            "cluster": context.cluster,
            "advisories": [
                {
                    "agent": a.agent_role,
                    "summary": a.summary,
                    "root_cause": a.root_cause,
                    "confidence": a.confidence,
                    "actions": a.recommended_actions,
                    "severity": a.severity,
                }
                for a in context.advisories
            ],
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    def get_investigation(self, alert_id: str) -> Optional[InvestigationContext]:
        """Retrieve an active investigation by alert ID."""
        return self.active_investigations.get(alert_id)

    def list_active_investigations(self) -> list[InvestigationContext]:
        """List all currently active investigations."""
        return [
            ctx
            for ctx in self.active_investigations.values()
            if ctx.status == "investigating"
        ]
