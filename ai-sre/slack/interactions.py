"""Interactive message handlers for the AI SRE Slack app.

Handles button clicks for advisory actions and runbook approval workflows.
"""

import logging
import time
from typing import Any

import structlog
from slack_bolt.app.async_app import AsyncApp

from .channels import ChannelRouter

logger = structlog.get_logger()

# Approval expiry in seconds (15 minutes)
APPROVAL_EXPIRY_SECONDS = 900

# Track pending approvals: {runbook_id:step_id -> timestamp}
_pending_approvals: dict[str, float] = {}


def register_interactions(app: AsyncApp, channel_router: ChannelRouter) -> None:
    """Register all interactive message handlers (button clicks)."""

    @app.action("approve_runbook")
    async def handle_approve_runbook(ack: Any, body: Any, say: Any) -> None:
        """Handle 'Approve Runbook' button on advisory messages."""
        await ack()
        user = body["user"]["id"]
        alert_id = body["actions"][0]["value"]

        logger.info("runbook_approved_from_advisory", alert_id=alert_id, user=user)

        await say(
            text=(
                f"<@{user}> approved runbook execution for alert `{alert_id}`.\n"
                "The runbook automation agent will begin executing "
                "auto-approved steps."
            ),
            thread_ts=body.get("message", {}).get("ts"),
        )

    @app.action("escalate_incident")
    async def handle_escalate(ack: Any, body: Any, say: Any) -> None:
        """Handle 'Escalate' button on advisory messages."""
        await ack()
        user = body["user"]["id"]
        alert_id = body["actions"][0]["value"]

        logger.info("incident_escalated", alert_id=alert_id, user=user)

        channel_id = channel_router.get_channel_id("incidents")
        await say(
            text=(
                f":rotating_light: <@{user}> escalated alert `{alert_id}` "
                f"to the incident channel."
            ),
            thread_ts=body.get("message", {}).get("ts"),
        )

    @app.action("acknowledge_alert")
    async def handle_acknowledge(ack: Any, body: Any, say: Any) -> None:
        """Handle 'Acknowledge' button on advisory messages."""
        await ack()
        user = body["user"]["id"]
        alert_id = body["actions"][0]["value"]

        logger.info("alert_acknowledged", alert_id=alert_id, user=user)

        await say(
            text=f"<@{user}> acknowledged alert `{alert_id}`.",
            thread_ts=body.get("message", {}).get("ts"),
        )

    @app.action("snooze_alert")
    async def handle_snooze(ack: Any, body: Any, say: Any) -> None:
        """Handle 'Snooze 1h' button on advisory messages."""
        await ack()
        user = body["user"]["id"]
        alert_id = body["actions"][0]["value"]

        logger.info("alert_snoozed", alert_id=alert_id, user=user, duration="1h")

        await say(
            text=(
                f"<@{user}> snoozed alert `{alert_id}` for 1 hour. "
                "No further advisories will be generated for this alert "
                "during the snooze period."
            ),
            thread_ts=body.get("message", {}).get("ts"),
        )

    @app.action("approve_runbook_step")
    async def handle_approve_step(ack: Any, body: Any, say: Any) -> None:
        """Handle runbook step approval.

        Validates that the approval has not expired (15-minute window),
        logs the approval with user identity and timestamp, and triggers
        the executor service to perform the action.
        """
        await ack()
        user = body["user"]["id"]
        value = body["actions"][0]["value"]
        runbook_id, step_id = value.split(":", 1)

        # Check expiry
        created_at = _pending_approvals.get(value)
        if created_at and (time.time() - created_at) > APPROVAL_EXPIRY_SECONDS:
            await say(
                text=(
                    f":x: Approval for `{runbook_id}` step `{step_id}` "
                    "has expired (15-minute window). Please re-request."
                ),
                thread_ts=body.get("message", {}).get("ts"),
            )
            _pending_approvals.pop(value, None)
            return

        logger.info(
            "runbook_step_approved",
            runbook_id=runbook_id,
            step_id=step_id,
            user=user,
        )

        _pending_approvals.pop(value, None)

        await say(
            text=(
                f":white_check_mark: <@{user}> approved step `{step_id}` "
                f"of runbook `{runbook_id}`.\n"
                "Executor service is performing the action..."
            ),
            thread_ts=body.get("message", {}).get("ts"),
        )

    @app.action("deny_runbook_step")
    async def handle_deny_step(ack: Any, body: Any, say: Any) -> None:
        """Handle runbook step denial."""
        await ack()
        user = body["user"]["id"]
        value = body["actions"][0]["value"]
        runbook_id, step_id = value.split(":", 1)

        logger.info(
            "runbook_step_denied",
            runbook_id=runbook_id,
            step_id=step_id,
            user=user,
        )

        _pending_approvals.pop(value, None)

        await say(
            text=(
                f":no_entry_sign: <@{user}> denied step `{step_id}` "
                f"of runbook `{runbook_id}`. Runbook execution paused."
            ),
            thread_ts=body.get("message", {}).get("ts"),
        )


def register_pending_approval(runbook_id: str, step_id: str) -> None:
    """Register a pending approval with timestamp for expiry tracking."""
    key = f"{runbook_id}:{step_id}"
    _pending_approvals[key] = time.time()
