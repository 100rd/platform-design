"""Event listeners for the AI SRE Slack app.

Handles app_mention events for on-call copilot and message.im events
for DM-based copilot conversations.
"""

import logging
from typing import Any

import structlog
from slack_bolt.app.async_app import AsyncApp

from .channels import ChannelRouter

logger = structlog.get_logger()


def register_event_listeners(
    app: AsyncApp, channel_router: ChannelRouter
) -> None:
    """Register event subscription handlers."""

    @app.event("app_mention")
    async def handle_mention(event: dict[str, Any], say: Any) -> None:
        """Handle @sre-bot mentions in channels.

        Triggers the on-call copilot for the mentioning user.
        Responds in a thread to keep the channel clean.
        """
        user = event.get("user", "")
        text = event.get("text", "")
        thread_ts = event.get("thread_ts") or event.get("ts")
        channel = event.get("channel", "")

        # Strip the bot mention from the text
        # Format is typically: <@BOT_USER_ID> actual message
        parts = text.split(">", 1)
        query = parts[1].strip() if len(parts) > 1 else text.strip()

        if not query:
            await say(
                text=(
                    f"Hi <@{user}>! I'm the AI SRE on-call copilot. "
                    "Ask me about alerts, incidents, or system health. "
                    "Try: `@sre-bot what's the current GPU fleet status?`"
                ),
                thread_ts=thread_ts,
            )
            return

        logger.info(
            "copilot_mention",
            user=user,
            channel=channel,
            query=query[:100],
        )

        # In production, forwards the query to the on-call copilot agent
        # and streams the response back to the thread.
        await say(
            text=(
                f"<@{user}> Investigating your question...\n"
                f"> {query}\n\n"
                "The on-call copilot agent is analyzing the situation. "
                "I'll reply in this thread with findings."
            ),
            thread_ts=thread_ts,
        )

    @app.event("message")
    async def handle_dm(event: dict[str, Any], say: Any) -> None:
        """Handle direct messages to the bot.

        Provides persistent DM-based copilot conversations with context
        maintained within the Slack thread.
        """
        # Only handle DM channel type
        channel_type = event.get("channel_type", "")
        if channel_type != "im":
            return

        # Ignore bot's own messages
        if event.get("bot_id"):
            return

        user = event.get("user", "")
        text = event.get("text", "")
        thread_ts = event.get("thread_ts") or event.get("ts")

        if not text:
            return

        logger.info("copilot_dm", user=user, query=text[:100])

        # In production, forwards to on-call copilot agent with
        # DM conversation context (thread history).
        await say(
            text=(
                "Let me look into that for you...\n\n"
                "The on-call copilot is gathering context from "
                "metrics, logs, and the knowledge base."
            ),
            thread_ts=thread_ts,
        )

    @app.event("reaction_added")
    async def handle_reaction(event: dict[str, Any], say: Any) -> None:
        """Handle reactions on advisory messages for feedback tracking.

        Reactions serve as human feedback on advisory quality:
        - thumbsup    = helpful/accurate
        - thumbsdown  = unhelpful/inaccurate
        - dart         = root cause correct
        - x            = root cause wrong
        """
        reaction = event.get("reaction", "")
        item = event.get("item", {})
        user = event.get("user", "")

        feedback_reactions = {
            "thumbsup": "helpful",
            "+1": "helpful",
            "thumbsdown": "unhelpful",
            "-1": "unhelpful",
            "dart": "root_cause_correct",
            "x": "root_cause_wrong",
        }

        feedback_type = feedback_reactions.get(reaction)
        if not feedback_type:
            return

        logger.info(
            "advisory_feedback",
            feedback_type=feedback_type,
            reaction=reaction,
            user=user,
            message_ts=item.get("ts"),
            channel=item.get("channel"),
        )
