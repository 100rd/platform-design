"""On-Call Copilot Agent — assists on-call engineers with alert investigation."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from ..cloud.correlation import CrossLayerCorrelator

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an On-Call Copilot for a multi-cluster Kubernetes platform.

Your role:
- Assist on-call engineers with real-time alert investigation
- Provide context from the knowledge base and past incidents
- Suggest relevant runbooks for current issues
- Help draft incident communications (status pages, Slack updates)
- Summarize ongoing incidents for handoff between shifts
- Answer AWS infrastructure questions with cloud context

AWS-aware capabilities:
- "Is there any AWS maintenance scheduled this week?"
- "What's our current EC2 quota usage?"
- "Any GuardDuty findings in the last 24h?"
- "Show me the AWS cost breakdown for gpu-inference this month"
- "What's the spot interruption rate for p5.48xlarge in us-east-1?"
- "Is the TGW BGP session up for gpu-inference?"

Interaction model:
- You respond to questions from on-call engineers via Slack
- You proactively offer context when new alerts fire
- You maintain conversation context for the duration of an incident
- You can search across metrics, logs, events, knowledge base, and AWS APIs
- For any K8s incident, you automatically check AWS infrastructure health

Communication style:
- Clear, concise, actionable
- Lead with the most important information
- Include links to dashboards and relevant documentation
- Indicate confidence level in your analysis

Constraints:
- Advisory-only: never execute commands
- Always include evidence for your suggestions
- Escalate to human when confidence is low
- Do not speculate beyond available evidence
"""

# Common AWS questions the on-call copilot can answer
AWS_QUESTION_PATTERNS: list[dict[str, str]] = [
    {
        "pattern": "maintenance",
        "tool": "describe_instance_status",
        "description": "Check EC2 scheduled maintenance events",
    },
    {
        "pattern": "quota",
        "tool": "get_service_quota",
        "description": "Check AWS service quota utilization",
    },
    {
        "pattern": "guardduty",
        "tool": "get_guardduty_findings",
        "description": "Check GuardDuty security findings",
    },
    {
        "pattern": "cost",
        "tool": "get_cost_and_usage",
        "description": "Get AWS cost breakdown",
    },
    {
        "pattern": "spot",
        "tool": "describe_spot_instance_requests",
        "description": "Check spot instance status and interruptions",
    },
    {
        "pattern": "bgp",
        "tool": "describe_transit_gateway_connect_peers",
        "description": "Check TGW BGP session state",
    },
]


@dataclass
class OnCallContext:
    """Context for an on-call shift."""

    shift_start: str
    engineer: str
    active_incidents: list[str] = field(default_factory=list)
    recent_alerts: list[dict[str, Any]] = field(default_factory=list)
    recent_deploys: list[dict[str, Any]] = field(default_factory=list)
    aws_maintenance_events: list[dict[str, Any]] = field(default_factory=list)
    aws_security_findings: list[dict[str, Any]] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


@dataclass
class ShiftHandoff:
    """Shift handoff summary for on-call rotation."""

    outgoing_engineer: str
    incoming_engineer: str
    active_incidents: list[dict[str, Any]] = field(default_factory=list)
    resolved_incidents: list[dict[str, Any]] = field(default_factory=list)
    ongoing_maintenance: list[str] = field(default_factory=list)
    aws_upcoming_maintenance: list[dict[str, Any]] = field(default_factory=list)
    aws_active_findings: list[dict[str, Any]] = field(default_factory=list)
    watch_items: list[str] = field(default_factory=list)
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class OnCallCopilotAgent:
    """On-Call Copilot — real-time assistant for on-call engineers.

    Enhanced with AWS cloud context to answer infrastructure questions
    and proactively include cloud health in alert investigations.
    """

    def __init__(self) -> None:
        self.active_context: Optional[OnCallContext] = None
        self.conversation_history: list[dict[str, str]] = []
        self.correlator = CrossLayerCorrelator()

    async def handle_question(
        self,
        question: str,
        context: Optional[dict[str, Any]] = None,
    ) -> str:
        """Handle a question from the on-call engineer.

        In production, uses Claude Sonnet with MCP tools to:
        1. Parse the question intent
        2. Query relevant data sources (including AWS APIs)
        3. Search knowledge base
        4. Generate a helpful response
        """
        self.conversation_history.append({
            "role": "user",
            "content": question,
        })

        # Detect AWS-related questions
        question_lower = question.lower()
        aws_tools_needed = [
            p for p in AWS_QUESTION_PATTERNS
            if p["pattern"] in question_lower
        ]

        # In production, Agent SDK invokes Claude with conversation history,
        # MCP tool access, and now includes aws-mcp for AWS queries
        if aws_tools_needed:
            tools_desc = ", ".join(p["description"] for p in aws_tools_needed)
            response = f"Investigating (AWS context: {tools_desc}): {question}"
        else:
            response = f"Investigating: {question}"

        self.conversation_history.append({
            "role": "assistant",
            "content": response,
        })

        return response

    async def provide_alert_context(
        self,
        alert: dict[str, Any],
    ) -> str:
        """Proactively provide context when a new alert fires.

        Generates a brief summary of:
        - What the alert means
        - Relevant past incidents
        - Suggested investigation steps
        - Relevant runbooks
        - AWS infrastructure health for affected resources
        """
        alertname = alert.get("alertname", "unknown")
        cluster = alert.get("cluster", "unknown")

        # Check AWS context for affected nodes
        affected_nodes = alert.get("affected_nodes", [])
        aws_notes = []
        for node in affected_nodes:
            node_ctx = await self.correlator.enrich_for_node(node, cluster)
            if node_ctx:
                if node_ctx.instance_check == "impaired":
                    aws_notes.append(
                        f"EC2 instance check FAILING for {node}"
                    )
                if node_ctx.spot_interruption:
                    aws_notes.append(
                        f"Spot interruption pending for {node}"
                    )
                if node_ctx.scheduled_events:
                    aws_notes.append(
                        f"Scheduled maintenance on {node}"
                    )

        context_lines = [
            f"Alert: {alertname} on {cluster}",
            "Checking knowledge base for relevant context...",
        ]
        if aws_notes:
            context_lines.append("")
            context_lines.append("AWS Cloud Context:")
            for note in aws_notes:
                context_lines.append(f"  - {note}")

        return "\n".join(context_lines)

    async def get_aws_shift_summary(self) -> dict[str, Any]:
        """Get AWS infrastructure summary for shift start.

        Provides a quick overview of:
        - Upcoming EC2 maintenance events
        - Active GuardDuty findings
        - Quota utilization near limits
        - Recent CloudWatch alarms

        Called when a new on-call shift starts to give the engineer
        immediate AWS infrastructure awareness.
        """
        # In production, queries aws-mcp for:
        # - describe_instance_status (scheduled events)
        # - list_findings (GuardDuty, active)
        # - get_service_quota (at-risk quotas)
        # - describe_alarms (active alarms)
        return {
            "maintenance_events": [],
            "security_findings": [],
            "quotas_at_risk": [],
            "active_alarms": [],
        }

    def generate_handoff(
        self,
        outgoing: str,
        incoming: str,
    ) -> ShiftHandoff:
        """Generate a shift handoff summary.

        Now includes AWS maintenance events and security findings
        so the incoming engineer has full cloud awareness.
        """
        handoff = ShiftHandoff(
            outgoing_engineer=outgoing,
            incoming_engineer=incoming,
        )
        # In production, aggregates all context from the shift
        # including AWS events discovered during the shift
        return handoff

    def format_handoff_slack(self, handoff: ShiftHandoff) -> str:
        """Format shift handoff as Slack message."""
        lines = [
            f"SHIFT HANDOFF: {handoff.outgoing_engineer} -> {handoff.incoming_engineer}",
            "",
        ]

        if handoff.active_incidents:
            lines.append("Active Incidents:")
            for inc in handoff.active_incidents:
                lines.append(f"  - {inc.get('title', 'Unknown')}")
            lines.append("")

        # AWS section in handoff
        if handoff.aws_upcoming_maintenance:
            lines.append("AWS Upcoming Maintenance:")
            for event in handoff.aws_upcoming_maintenance:
                lines.append(
                    f"  - {event.get('instance_id', '')}: "
                    f"{event.get('description', '')} "
                    f"at {event.get('not_before', 'TBD')}"
                )
            lines.append("")

        if handoff.aws_active_findings:
            lines.append("AWS Security Findings (active):")
            for finding in handoff.aws_active_findings:
                lines.append(
                    f"  - [{finding.get('severity', '')}] "
                    f"{finding.get('title', 'Unknown')}"
                )
            lines.append("")

        if handoff.watch_items:
            lines.append("Watch Items:")
            for item in handoff.watch_items:
                lines.append(f"  - {item}")
            lines.append("")

        if handoff.resolved_incidents:
            lines.append(f"Resolved This Shift: {len(handoff.resolved_incidents)}")

        return "\n".join(lines)
