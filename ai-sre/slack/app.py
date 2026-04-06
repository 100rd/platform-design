"""Slack Bolt application for the AI SRE system.

Provides the primary human interface: receives advisories from agents,
enables interactive approval workflows, and supports on-call copilot
conversations via DM and @-mentions.
"""

import logging
import os

import structlog
from slack_bolt.app.async_app import AsyncApp
from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler

from .channels import ChannelRouter
from .commands import register_commands
from .interactions import register_interactions
from .listeners import register_event_listeners

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

logger = structlog.get_logger()


def create_app() -> AsyncApp:
    """Create and configure the Slack Bolt application.

    Uses Socket Mode for HA deployment (no public webhook URL needed).
    Tokens are loaded from environment variables, injected via
    ExternalSecret from AWS Secrets Manager.
    """
    app = AsyncApp(
        token=os.environ.get("SLACK_BOT_TOKEN", ""),
        name="AI SRE Bot",
    )

    channel_router = ChannelRouter()

    register_commands(app, channel_router)
    register_interactions(app, channel_router)
    register_event_listeners(app, channel_router)

    logger.info("slack_app_created")
    return app


async def start_socket_mode(app: AsyncApp) -> None:
    """Start the Slack app in Socket Mode for HA deployment."""
    handler = AsyncSocketModeHandler(
        app=app,
        app_token=os.environ.get("SLACK_APP_TOKEN", ""),
    )
    logger.info("starting_socket_mode")
    await handler.start_async()
