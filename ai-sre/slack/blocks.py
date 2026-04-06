"""Slack Block Kit message builders for AI SRE advisories.

Builds rich interactive messages with severity badges, collapsible
sections, and action buttons for approval workflows.
"""

from typing import Any, Optional


SEVERITY_EMOJI = {
    "critical": ":red_circle:",
    "warning": ":large_yellow_circle:",
    "info": ":large_green_circle:",
}


def build_advisory_blocks(
    alert_id: str,
    alert_name: str,
    cluster: str,
    severity: str,
    summary: str,
    root_cause: Optional[str] = None,
    confidence: float = 0.0,
    recommended_actions: Optional[list[str]] = None,
    related_incidents: Optional[list[str]] = None,
    agent_role: str = "orchestrator",
) -> list[dict[str, Any]]:
    """Build Block Kit blocks for an agent advisory message.

    Produces a structured advisory with severity badge, collapsible
    sections for signals/root cause/recommendations, and action buttons.
    """
    emoji = SEVERITY_EMOJI.get(severity, ":large_green_circle:")
    blocks: list[dict[str, Any]] = []

    # Header
    blocks.append({
        "type": "header",
        "text": {
            "type": "plain_text",
            "text": f"{alert_name} on {cluster}",
        },
    })

    # Severity + agent badge
    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": (
                f"{emoji} *Severity*: {severity.upper()} | "
                f"*Agent*: {agent_role} | "
                f"*Alert ID*: `{alert_id}`"
            ),
        },
    })

    blocks.append({"type": "divider"})

    # Summary
    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": f"*Summary*\n{summary}",
        },
    })

    # Root cause
    if root_cause:
        confidence_pct = f"{confidence * 100:.0f}%"
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    f"*Root Cause* (confidence: {confidence_pct})\n{root_cause}"
                ),
            },
        })

    # Recommended actions
    if recommended_actions:
        action_text = "\n".join(
            f"{i + 1}. {action}" for i, action in enumerate(recommended_actions)
        )
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Recommended Actions*\n{action_text}",
            },
        })

    # Related incidents
    if related_incidents:
        incidents_text = "\n".join(f"- {inc}" for inc in related_incidents)
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Related Past Incidents*\n{incidents_text}",
            },
        })

    blocks.append({"type": "divider"})

    # Action buttons
    blocks.append({
        "type": "actions",
        "block_id": f"advisory_actions_{alert_id}",
        "elements": [
            {
                "type": "button",
                "text": {"type": "plain_text", "text": "Approve Runbook"},
                "style": "primary",
                "action_id": "approve_runbook",
                "value": alert_id,
            },
            {
                "type": "button",
                "text": {"type": "plain_text", "text": "Escalate"},
                "style": "danger",
                "action_id": "escalate_incident",
                "value": alert_id,
            },
            {
                "type": "button",
                "text": {"type": "plain_text", "text": "Acknowledge"},
                "action_id": "acknowledge_alert",
                "value": alert_id,
            },
            {
                "type": "button",
                "text": {"type": "plain_text", "text": "Snooze 1h"},
                "action_id": "snooze_alert",
                "value": alert_id,
            },
        ],
    })

    return blocks


def build_runbook_approval_blocks(
    runbook_id: str,
    step_id: str,
    step_name: str,
    step_command: str,
    target_cluster: str,
) -> list[dict[str, Any]]:
    """Build Block Kit blocks for a runbook step approval request.

    Agents post this when a runbook step requires human approval
    before execution (e.g., cordon, drain, scale operations).
    """
    blocks: list[dict[str, Any]] = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"Runbook Approval Required: {step_name}",
            },
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    f"*Runbook*: `{runbook_id}`\n"
                    f"*Step*: `{step_id}`\n"
                    f"*Cluster*: `{target_cluster}`"
                ),
            },
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Command to execute:*\n```{step_command}```",
            },
        },
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": ":warning: This approval expires in 15 minutes.",
                },
            ],
        },
        {
            "type": "actions",
            "block_id": f"runbook_approval_{runbook_id}_{step_id}",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Approve"},
                    "style": "primary",
                    "action_id": "approve_runbook_step",
                    "value": f"{runbook_id}:{step_id}",
                },
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "Deny"},
                    "style": "danger",
                    "action_id": "deny_runbook_step",
                    "value": f"{runbook_id}:{step_id}",
                },
            ],
        },
    ]

    return blocks


def build_status_blocks(
    clusters: list[dict[str, Any]],
    active_investigations: int,
    agents_online: int,
) -> list[dict[str, Any]]:
    """Build Block Kit blocks for /sre status response."""
    blocks: list[dict[str, Any]] = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": "AI SRE System Status"},
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": (
                    f"*Active Investigations*: {active_investigations}\n"
                    f"*Agents Online*: {agents_online}"
                ),
            },
        },
        {"type": "divider"},
    ]

    for cluster in clusters:
        name = cluster.get("name", "unknown")
        health = cluster.get("health", "unknown")
        emoji = ":large_green_circle:" if health == "healthy" else ":red_circle:"
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"{emoji} *{name}*: {health}",
            },
        })

    return blocks
