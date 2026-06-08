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
class Blackboard:
    """Shared Blackboard pattern for collaborative incident investigation.

    Holds incident signals, the target infrastructure subgraph, and agent findings.
    """

    incident_signals: list[dict[str, Any]] = field(default_factory=list)
    infrastructure_subgraph: dict[str, Any] = field(default_factory=dict)
    findings: list[Advisory] = field(default_factory=list)

    def add_signal(self, signal: dict[str, Any]) -> None:
        """Add an incident signal (e.g., alerts, logs, metrics) to the blackboard."""
        self.incident_signals.append(signal)

    def update_infrastructure_subgraph(self, key: str, value: Any) -> None:
        """Update/enrich the target infrastructure subgraph with resources or topology details."""
        self.infrastructure_subgraph[key] = value

    def add_finding(self, finding: Advisory) -> None:
        """Write an agent finding (advisory) to the blackboard."""
        self.findings.append(finding)

    def get_findings(self) -> list[Advisory]:
        """Read all agent findings (advisories) from the blackboard."""
        return self.findings

    def get_signals(self) -> list[dict[str, Any]]:
        """Read all incident signals from the blackboard."""
        return self.incident_signals

    def get_subgraph(self) -> dict[str, Any]:
        """Read the target infrastructure subgraph from the blackboard."""
        return self.infrastructure_subgraph


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
    blackboard: Blackboard = field(default_factory=Blackboard)

    def __post_init__(self) -> None:
        # Link the findings of the blackboard to the advisories list to ensure full backward compatibility
        self.blackboard.findings = self.advisories
        # Seed the blackboard with the initial incident alert signal
        self.blackboard.add_signal({
            "type": "alert",
            "alert_id": self.alert_id,
            "alert_name": self.alert_name,
            "cluster": self.cluster,
            "namespace": self.namespace,
            "labels": self.labels,
        })


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
        - ec2_*, ebs_*, spot_*   -> AWS Cloud Agent
        - guardduty_*, securityhub_* -> AWS Cloud Agent
        - aws_quota_*            -> AWS Cloud Agent
        - cloudwatch_*           -> AWS Cloud Agent
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
            (["ec2_", "ebs_", "spot_"], AgentRole.AWS_CLOUD),
            (["guardduty_", "securityhub_"], AgentRole.AWS_CLOUD),
            (["aws_quota_"], AgentRole.AWS_CLOUD),
            (["cloudwatch_"], AgentRole.AWS_CLOUD),
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
        and runs the specialized agents using the shared Blackboard context.
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

        # Run primary specialist SRE agent on the shared blackboard
        await self._run_agent(target_role, context.blackboard)

        # For AWS cloud alerts, also request cross-layer enrichment
        # from the AWS Cloud Agent even when routing to another agent
        if target_role != AgentRole.AWS_CLOUD:
            enrichment_needed = self._needs_aws_enrichment(alert)
            if enrichment_needed:
                context.enrichment["aws_cloud_check_requested"] = True
                logger.info(
                    "Also requesting AWS cloud enrichment for alert '%s'",
                    alert_name,
                )
                # Run the AWS Cloud Agent on the same blackboard context
                await self._run_agent(AgentRole.AWS_CLOUD, context.blackboard)

        return context

    async def _run_agent(self, role: AgentRole, blackboard: Blackboard) -> None:
        """Run a specialized SRE agent, allowing it to read from and write findings to the shared blackboard.

        In production, this would invoke the Claude Agent SDK to run the specialized agent
        with its specific MCP tools. Here, we simulate the agent logic where it reads from
        the blackboard, updates the infrastructure subgraph, and writes findings.
        """
        # Read incident signals and target infrastructure subgraph from the blackboard
        signals = blackboard.get_signals()
        subgraph = blackboard.get_subgraph()

        logger.info(
            "Running specialist SRE agent '%s' on shared blackboard context. Signals: %d, Subgraph keys: %s",
            role.value,
            len(signals),
            list(subgraph.keys()),
        )

        # 1. Analyze signals to determine the context
        alert_name = "unknown"
        cluster = "unknown"
        for signal in signals:
            if signal.get("type") == "alert":
                alert_name = signal.get("alert_name", "unknown")
                cluster = signal.get("cluster", "unknown")
                break

        # 2. Simulate agent updating the target infrastructure subgraph on the blackboard
        if role == AgentRole.AWS_CLOUD:
            blackboard.update_infrastructure_subgraph(
                "aws_resources",
                {
                    "nodes": [
                        {"id": f"aws-ec2-{cluster}", "type": "EC2Instance", "status": "running"},
                        {"id": f"aws-ebs-{cluster}", "type": "EBSVolume", "status": "attached"},
                    ],
                    "edges": [
                        {"source": f"aws-ec2-{cluster}", "target": f"aws-ebs-{cluster}", "relation": "uses"}
                    ]
                }
            )
        else:
            # For K8s or other layers, update the K8s subgraph
            blackboard.update_infrastructure_subgraph(
                "k8s_resources",
                {
                    "nodes": [
                        {"id": f"k8s-pod-{alert_name}", "type": "Pod", "status": "CrashLoopBackOff"},
                        {"id": f"k8s-node-{cluster}", "type": "Node", "status": "Ready"},
                    ],
                    "edges": [
                        {"source": f"k8s-pod-{alert_name}", "target": f"k8s-node-{cluster}", "relation": "scheduled_on"}
                    ]
                }
            )

        # 3. Simulate writing findings (Advisory) back to the blackboard
        summary = f"Specialist SRE Agent {role.value} analyzed the incident."
        root_cause = f"Potential root cause related to {alert_name} in cluster {cluster} identified by {role.value}."

        advisory = Advisory(
            agent_role=role.value,
            summary=summary,
            root_cause=root_cause,
            confidence=0.8,
            recommended_actions=[
                f"Check logs for {role.value} related components",
                "Review recent platform deployment metrics"
            ],
            severity="warning"
        )
        blackboard.add_finding(advisory)

    def _needs_aws_enrichment(self, alert: dict[str, Any]) -> bool:
        """Determine if an alert would benefit from AWS cloud context.

        Most K8s-layer alerts can benefit from checking the underlying
        EC2/EBS/network health to rule out infrastructure root causes.
        """
        alert_name = alert.get("labels", {}).get("alertname", "").lower()
        # Pod crashes, node issues, and network problems often have AWS root causes
        enrichment_patterns = [
            "kube_pod_",
            "container_",
            "node_",
            "kubelet_",
            "cilium_",
            "network_",
            "gpu_",
            "dcgm_",
        ]
        return any(alert_name.startswith(p) for p in enrichment_patterns)

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
            "infrastructure_subgraph": context.blackboard.get_subgraph(),
            "aws_enrichment": context.enrichment.get(
                "aws_cloud_check_requested", False
            ),
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
