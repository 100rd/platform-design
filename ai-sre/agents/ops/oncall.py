"""On-Call Copilot Agent — assists on-call engineers with alert investigation."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an On-Call Copilot for a multi-cluster Kubernetes platform.

Your role:
- Assist on-call engineers with real-time alert investigation
- Provide context from the knowledge base and past incidents
- Suggest relevant runbooks for current issues
- Help draft incident communications (status pages, Slack updates)
- Summarize ongoing incidents for handoff between shifts

Interaction model:
- You respond to questions from on-call engineers via Slack
- You proactively offer context when new alerts fire
- You maintain conversation context for the duration of an incident
- You can search across metrics, logs, events, and knowledge base

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


@dataclass
class OnCallContext:
    """Context for an on-call shift."""

    shift_start: str
    engineer: str
    active_incidents: list[str] = field(default_factory=list)
    recent_alerts: list[dict[str, Any]] = field(default_factory=list)
    recent_deploys: list[dict[str, Any]] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


@dataclass
class ShiftHandoff:
    """Shift handoff summary for on-call rotation."""

    outgoing_engineer: str
    incoming_engineer: str
    active_incidents: list[dict[str, Any]] = field(default_factory=list)
    resolved_incidents: list[dict[str, Any]] = field(default_factory=list)
    ongoing_maintenance: list[str] = field(default_factory=list)
    watch_items: list[str] = field(default_factory=list)
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class OnCallCopilotAgent:
    """On-Call Copilot — real-time assistant for on-call engineers."""

    def __init__(self) -> None:
        self.active_context: Optional[OnCallContext] = None
        self.conversation_history: list[dict[str, str]] = []

    async def handle_question(
        self,
        question: str,
        context: Optional[dict[str, Any]] = None,
    ) -> str:
        """Handle a question from the on-call engineer.

        In production, uses Claude Sonnet with MCP tools to:
        1. Parse the question intent
        2. Query relevant data sources
        3. Search knowledge base
        4. Generate a helpful response
        """
        self.conversation_history.append({
            "role": "user",
            "content": question,
        })

        # In production, Agent SDK invokes Claude with conversation history
        # and MCP tool access
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
        """
        alertname = alert.get("alertname", "unknown")
        cluster = alert.get("cluster", "unknown")

        # In production, queries knowledge base and incident history
        return (
            f"Alert: {alertname} on {cluster}\n"
            f"Checking knowledge base for relevant context..."
        )

    def generate_handoff(
        self,
        outgoing: str,
        incoming: str,
    ) -> ShiftHandoff:
        """Generate a shift handoff summary."""
        handoff = ShiftHandoff(
            outgoing_engineer=outgoing,
            incoming_engineer=incoming,
        )
        # In production, aggregates all context from the shift
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

        if handoff.watch_items:
            lines.append("Watch Items:")
            for item in handoff.watch_items:
                lines.append(f"  - {item}")
            lines.append("")

        if handoff.resolved_incidents:
            lines.append(f"Resolved This Shift: {len(handoff.resolved_incidents)}")

        return "\n".join(lines)
