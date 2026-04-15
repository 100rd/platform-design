"""Slack reaction and button handlers that feed into SREAnalytics.

Registers new action IDs alongside the existing interactions.py handlers.
Import and call ``register_analytics_interactions(app, analytics)`` from
slack/main.py after the existing registrations.

Emoji → feedback_value mapping
-------------------------------
    +1 / thumbsup       → helpful
    -1 / thumbsdown     → not_helpful
    dart                → correct_rca
    x                   → wrong_rca
"""

from __future__ import annotations

import logging
from typing import Any

import structlog
from slack_bolt.app.async_app import AsyncApp

from .tracker import SREAnalytics

logger = structlog.get_logger()

# Map Slack reaction names to structured feedback_value
_REACTION_MAP: dict[str, str] = {
    "+1": "helpful",
    "thumbsup": "helpful",
    "-1": "not_helpful",
    "thumbsdown": "not_helpful",
    "dart": "correct_rca",
    "x": "wrong_rca",
    "white_check_mark": "correct_rca",
}


def register_analytics_interactions(
    app: AsyncApp,
    analytics: SREAnalytics,
) -> None:
    """Attach Slack event listeners for analytics feedback collection.

    Registers:
    - reaction_added   → feedback_type=reaction
    - mark_resolved    → resolution tracking
    - mark_false_positive → resolution tracking + feedback
    - needs_followup   → finding status note (no feedback row)
    """

    @app.event("reaction_added")
    async def handle_reaction(event: dict[str, Any], client: Any) -> None:
        """Capture Slack emoji reactions on advisory messages."""
        reaction = event.get("item_user", {})
        reaction_name = event.get("reaction", "")
        feedback_value = _REACTION_MAP.get(reaction_name)
        if not feedback_value:
            return  # Ignore non-feedback reactions

        user_id: str = event.get("user", "unknown")
        item = event.get("item", {})
        message_ts: str = item.get("ts", "")
        channel_id: str = item.get("channel", "")

        # Look up the advisory message to get finding_id metadata
        finding_id, invocation_id, agent_role, cluster = await _resolve_message_metadata(
            client, channel_id, message_ts
        )
        if not finding_id:
            logger.debug(
                "analytics_reaction_skipped",
                reason="no_finding_id_in_message",
                channel=channel_id,
                ts=message_ts,
            )
            return

        await analytics.on_feedback(
            finding_id=finding_id,
            invocation_id=invocation_id,
            agent_role=agent_role,
            cluster=cluster,
            feedback_type="reaction",
            feedback_value=feedback_value,
            feedback_by=user_id,
        )
        logger.info(
            "analytics_feedback_recorded",
            reaction=reaction_name,
            feedback_value=feedback_value,
            finding_id=finding_id,
            user=user_id,
        )

    @app.action("mark_resolved")
    async def handle_mark_resolved(ack: Any, body: Any) -> None:
        """Handle 'Mark Resolved' button on advisory messages."""
        await ack()
        user_id: str = body["user"]["id"]
        value: str = body["actions"][0]["value"]
        finding_id, invocation_id, agent_role, cluster = _parse_action_value(value)

        await analytics.on_resolution(
            finding_id=finding_id,
            invocation_id=invocation_id,
            agent_role=agent_role,
            cluster=cluster,
            resolution_type="manual_fix",
            resolved_by=user_id,
        )
        logger.info(
            "finding_marked_resolved", finding_id=finding_id, user=user_id
        )

    @app.action("mark_false_positive")
    async def handle_false_positive(ack: Any, body: Any) -> None:
        """Handle 'False Positive' button on advisory messages."""
        await ack()
        user_id: str = body["user"]["id"]
        value: str = body["actions"][0]["value"]
        finding_id, invocation_id, agent_role, cluster = _parse_action_value(value)

        await analytics.on_resolution(
            finding_id=finding_id,
            invocation_id=invocation_id,
            agent_role=agent_role,
            cluster=cluster,
            resolution_type="false_positive",
            resolved_by=user_id,
        )
        # Also write an explicit feedback row
        await analytics.on_feedback(
            finding_id=finding_id,
            invocation_id=invocation_id,
            agent_role=agent_role,
            cluster=cluster,
            feedback_type="button",
            feedback_value="false_positive",
            feedback_by=user_id,
        )
        logger.info(
            "finding_marked_false_positive", finding_id=finding_id, user=user_id
        )


# ── helpers ──────────────────────────────────────────────────────────────────

def _parse_action_value(value: str) -> tuple[str, str, str, str]:
    """Parse pipe-separated action value: finding_id|invocation_id|agent_role|cluster."""
    parts = value.split("|", 3)
    if len(parts) == 4:
        return parts[0], parts[1], parts[2], parts[3]
    return value, "", "unknown", "unknown"


async def _resolve_message_metadata(
    client: Any, channel_id: str, message_ts: str
) -> tuple[str, str, str, str]:
    """Retrieve finding metadata stored in the advisory message's metadata block.

    Advisory messages are expected to store a JSON metadata block with keys:
        finding_id, invocation_id, agent_role, cluster

    Falls back to empty strings if metadata is not present.
    """
    try:
        resp = await client.conversations_history(
            channel=channel_id,
            latest=message_ts,
            inclusive=True,
            limit=1,
        )
        messages = resp.get("messages", [])
        if not messages:
            return "", "", "unknown", "unknown"

        msg = messages[0]
        metadata = msg.get("metadata", {}).get("event_payload", {})
        return (
            metadata.get("finding_id", ""),
            metadata.get("invocation_id", ""),
            metadata.get("agent_role", "unknown"),
            metadata.get("cluster", "unknown"),
        )
    except Exception:
        logging.getLogger(__name__).debug(
            "failed_to_resolve_message_metadata",
            channel=channel_id,
            ts=message_ts,
            exc_info=True,
        )
        return "", "", "unknown", "unknown"
