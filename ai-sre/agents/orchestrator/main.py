"""Entry point for the AI SRE Orchestrator service."""

import logging
import os
from contextlib import asynccontextmanager

import structlog
import yaml
from fastapi import FastAPI
from prometheus_client import make_asgi_app

from .agent import SREOrchestrator

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

logger = structlog.get_logger()

orchestrator: SREOrchestrator | None = None


def load_config(path: str) -> dict:
    """Load YAML configuration file."""
    with open(path) as f:
        return yaml.safe_load(f)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan — initialize orchestrator on startup."""
    global orchestrator

    config_path = os.environ.get("AGENT_CONFIG_PATH", "/etc/ai-sre/agents.yaml")
    logger.info("loading_config", path=config_path)

    orchestrator = SREOrchestrator()
    logger.info("orchestrator_initialized", agent_count=len(orchestrator.agents))

    yield

    logger.info("shutting_down")
    orchestrator = None


app = FastAPI(
    title="AI SRE Orchestrator",
    version="0.1.0",
    lifespan=lifespan,
)

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)


@app.get("/healthz")
async def healthz():
    """Liveness probe."""
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    """Readiness probe."""
    if orchestrator is None:
        return {"status": "not_ready"}, 503
    return {"status": "ready"}


@app.get("/api/v1/status")
async def status():
    """Return current orchestrator status."""
    if orchestrator is None:
        return {"status": "not_initialized"}

    active = orchestrator.list_active_investigations()
    return {
        "status": "running",
        "active_investigations": len(active),
        "registered_agents": len(orchestrator.agents),
    }
