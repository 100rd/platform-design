"""Incident Response Agent — performs root cause analysis with multi-signal correlation."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from ..cloud.correlation import CrossLayerCorrelator, CrossLayerEnrichment

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an SRE Incident Response specialist analyzing production incidents
across a multi-cluster Kubernetes platform (platform, gpu-inference, blockchain, gpu-analysis).

Your investigation process:
1. Parse alert context (cluster, namespace, service, severity)
2. Correlate metrics from VictoriaMetrics (error rates, resource utilization, GPU health)
3. Analyze logs from ClickHouse (error patterns, stack traces)
4. Check Kubernetes events (pod restarts, OOMKilled, evictions, node conditions)
5. Correlate with recent changes (git commits, ArgoCD syncs, Helm releases)
6. Search incident history for similar past incidents and resolutions
7. CHECK AWS CLOUD CONTEXT for underlying infrastructure issues:
   - EC2 instance health for affected nodes (status checks, maintenance events)
   - EBS volume status for affected PVCs (impairment, IO degradation)
   - Recent CloudTrail events (IAM changes, SG modifications)
   - Active GuardDuty findings for affected instances
8. Generate ranked root cause hypotheses with confidence levels
9. Recommend remediation steps (advisory only — never execute)

Cross-layer correlation rules:
- Pod CrashLoopBackOff + EBS volume impaired -> root cause: EBS, not app
- Network timeout + TGW BGP session down -> root cause: networking, not app
- Multiple node failures + EC2 maintenance -> root cause: planned maintenance
- GPU errors + EC2 instance check failing -> root cause: hardware, file AWS ticket

Constraints:
- You are advisory-only. Never execute commands autonomously.
- Always show evidence for your conclusions.
- Use structured thinking to correlate signals chronologically.
- Consider error budget impact in your assessment.
- Reference past incidents when similar patterns are found.
- Always include AWS cloud context in your investigation.
"""


@dataclass
class Signal:
    """A correlated signal from an investigation."""

    source: str  # metrics, logs, events, changes, history, aws_cloud
    description: str
    timestamp: Optional[str] = None
    severity: str = "info"
    data: dict[str, Any] = field(default_factory=dict)


@dataclass
class RootCauseHypothesis:
    """A ranked root cause hypothesis."""

    description: str
    confidence: str  # HIGH, MEDIUM, LOW
    evidence: list[str] = field(default_factory=list)
    category: str = ""  # deployment, resource, network, hardware, config, aws_infra


@dataclass
class IncidentAdvisory:
    """Structured advisory output from an incident investigation."""

    alert_id: str
    alertname: str
    cluster: str
    namespace: Optional[str] = None
    service: Optional[str] = None
    severity: str = "warning"
    signals: list[Signal] = field(default_factory=list)
    hypotheses: list[RootCauseHypothesis] = field(default_factory=list)
    recommended_actions: list[str] = field(default_factory=list)
    error_budget_impact: Optional[dict[str, Any]] = None
    similar_incidents: list[dict[str, Any]] = field(default_factory=list)
    aws_enrichment: Optional[CrossLayerEnrichment] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class IncidentResponseAgent:
    """Incident Response Agent — multi-signal RCA for production incidents.

    Uses Claude Sonnet via the Agent SDK with MCP tools for:
    - Metrics queries (VictoriaMetrics via metrics-mcp)
    - Log search (ClickHouse via metrics-mcp)
    - K8s resource inspection (kubernetes-mcp)
    - Change correlation (git-mcp)
    - Incident history (runbook-mcp / knowledge base)
    - AWS cloud context (aws-mcp via CrossLayerCorrelator)
    """

    def __init__(self) -> None:
        self.active_investigations: dict[str, IncidentAdvisory] = {}
        self.correlator = CrossLayerCorrelator()

    async def investigate(self, alert: dict[str, Any]) -> IncidentAdvisory:
        """Run a full incident investigation for an alert.

        Executes the investigation workflow:
        1. Alert context parsing
        2. Metrics correlation
        3. Log analysis
        4. Event correlation
        5. Change correlation
        6. Historical pattern matching
        7. AWS cloud context enrichment
        """
        alert_id = alert.get("alert_id", "unknown")
        alertname = alert.get("alertname", "unknown")
        cluster = alert.get("cluster", "unknown")
        namespace = alert.get("namespace")
        labels = alert.get("labels", {})

        advisory = IncidentAdvisory(
            alert_id=alert_id,
            alertname=alertname,
            cluster=cluster,
            namespace=namespace,
            severity=labels.get("severity", "warning"),
        )

        self.active_investigations[alert_id] = advisory

        # Step 1: Alert context
        logger.info(
            "Starting investigation: alert=%s cluster=%s namespace=%s",
            alertname,
            cluster,
            namespace,
        )

        # Steps 2-6 would invoke MCP tools via the Agent SDK
        # In production:
        # - metrics-mcp: query_metrics for error rates, resource usage
        # - metrics-mcp: query_logs for error patterns
        # - kubernetes-mcp: list_events, get_pods for K8s state
        # - git-mcp: recent commits affecting the namespace
        # - runbook-mcp: search_incidents for similar past incidents

        # Step 7: AWS cloud context enrichment
        affected_nodes = alert.get("affected_nodes", [])
        affected_pvcs = alert.get("affected_pvcs", [])
        enrichment = await self.correlator.full_enrichment(
            cluster=cluster,
            node_names=affected_nodes if affected_nodes else None,
            pvc_names=affected_pvcs if affected_pvcs else None,
        )
        advisory.aws_enrichment = enrichment

        # Add AWS correlation notes as signals
        for note in enrichment.correlation_notes:
            advisory.signals.append(Signal(
                source="aws_cloud",
                description=note,
                severity="warning",
            ))

        return advisory

    async def correlate_signals(
        self, advisory: IncidentAdvisory
    ) -> list[RootCauseHypothesis]:
        """Analyze correlated signals and generate root cause hypotheses.

        The agent SDK would invoke Claude Sonnet with the collected signals
        (including AWS cloud context) and ask it to generate ranked hypotheses.

        AWS enrichment adds infrastructure-level hypotheses:
        - If EC2 checks failing: hardware hypothesis ranked high
        - If EBS impaired: storage hypothesis ranked high
        - If BGP down: network hypothesis ranked high
        """
        # In production, this is handled by the Claude model with
        # all signals in context, generating structured hypotheses
        return advisory.hypotheses

    def format_slack_advisory(self, advisory: IncidentAdvisory) -> str:
        """Format an advisory as a Slack message."""
        severity_emoji = {
            "critical": "RED CIRCLE",
            "warning": "WARNING",
            "info": "INFO",
        }

        lines = [
            f"INCIDENT ADVISORY: {advisory.alertname} "
            f"in {advisory.cluster}/{advisory.namespace or 'cluster-wide'}",
            "",
            "Signals Correlated:",
        ]

        for signal in advisory.signals:
            lines.append(f"  - [{signal.source}] {signal.description}")

        if advisory.hypotheses:
            top = advisory.hypotheses[0]
            lines.extend([
                "",
                f"Root Cause (confidence: {top.confidence}):",
                f"  {top.description}",
            ])

        # Include AWS cloud context in output
        if advisory.aws_enrichment and advisory.aws_enrichment.correlation_notes:
            lines.extend(["", "AWS Cloud Context:"])
            for note in advisory.aws_enrichment.correlation_notes:
                lines.append(f"  - {note}")

        if advisory.recommended_actions:
            lines.extend(["", "Recommended Actions:"])
            for i, action in enumerate(advisory.recommended_actions, 1):
                lines.append(f"  {i}. {action}")

        if advisory.error_budget_impact:
            budget = advisory.error_budget_impact
            lines.extend([
                "",
                "Error Budget Impact:",
                f"  {budget.get('summary', 'N/A')}",
            ])

        return "\n".join(lines)
