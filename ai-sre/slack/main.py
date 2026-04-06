"""Entry point for the AI SRE Slack Bolt application."""

import asyncio
import logging
import os

import structlog
from fastapi import FastAPI
from prometheus_client import make_asgi_app

from .app import create_app, start_socket_mode

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

logger = structlog.get_logger()


# FastAPI app for health checks and metrics
api = FastAPI(
    title="AI SRE Slack App",
    version="0.1.0",
)

metrics_app = make_asgi_app()
api.mount("/metrics", metrics_app)


@api.get("/healthz")
async def healthz():
    """Liveness probe."""
    return {"status": "ok"}


@api.get("/readyz")
async def readyz():
    """Readiness probe — checks Slack connection is active."""
    bot_token = os.environ.get("SLACK_BOT_TOKEN", "")
    if not bot_token:
        return {"status": "not_ready", "reason": "missing_slack_bot_token"}
    return {"status": "ready"}


def main() -> None:
    """Start the Slack Bolt app alongside the health-check API."""
    slack_app = create_app()

    async def run() -> None:
        await start_socket_mode(slack_app)

    logger.info("starting_slack_app")
    asyncio.run(run())


if __name__ == "__main__":
    main()
