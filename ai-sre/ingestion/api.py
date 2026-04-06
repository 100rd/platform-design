"""Alert ingestion API — receives Alertmanager webhooks and triggers agent investigations."""

import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any

import structlog
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from prometheus_client import make_asgi_app

from .dedup import AlertDeduplicator
from .enrichment import enrich_alert
from .metrics import (
    alert_enrichment_duration_seconds,
    alerts_deduplicated_total,
    alerts_received_total,
    webhook_requests_total,
)
from .models import (
    AlertmanagerWebhook,
    AlertSeverity,
    AlertStatus,
    EnrichedAlert,
)
from .router import route_alert

structlog.configure(
    processors=[
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
)

logger = structlog.get_logger()

# Configuration
RATE_LIMIT_PER_MINUTE = int(os.environ.get("ALERT_RATE_LIMIT", "100"))
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")

# Global state
deduplicator = AlertDeduplicator()
_request_timestamps: list[float] = []


def check_rate_limit() -> bool:
    """Simple sliding-window rate limiter."""
    now = time.time()
    cutoff = now - 60
    # Remove old timestamps
    while _request_timestamps and _request_timestamps[0] < cutoff:
        _request_timestamps.pop(0)
    if len(_request_timestamps) >= RATE_LIMIT_PER_MINUTE:
        return False
    _request_timestamps.append(now)
    return True


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan."""
    logger.info("alert_ingestion_starting", rate_limit=RATE_LIMIT_PER_MINUTE)
    yield
    logger.info("alert_ingestion_stopping")


app = FastAPI(
    title="AI SRE Alert Ingestion",
    version="0.1.0",
    lifespan=lifespan,
)

# Mount Prometheus metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)


@app.get("/healthz")
async def healthz():
    """Liveness probe."""
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    """Readiness probe."""
    return {"status": "ready"}


@app.post("/api/v1/alerts")
async def receive_alerts(
    webhook: AlertmanagerWebhook,
    request: Request,
) -> dict[str, Any]:
    """Receive alerts from Alertmanager webhook.

    Accepts both VictoriaMetrics VMAlertmanager and Prometheus Alertmanager
    webhook format. Each alert is:
    1. Rate-limited (100/min default)
    2. Deduplicated (5-min window by alertname+cluster+namespace)
    3. Enriched with context (resource utilization, recent similar alerts)
    4. Routed to the appropriate specialized agent
    """
    # Rate limiting
    if not check_rate_limit():
        webhook_requests_total.labels(status="rate_limited").inc()
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Max 100 alerts/minute.",
        )

    webhook_requests_total.labels(status="accepted").inc()

    processed = []
    deduplicated = 0

    for alert in webhook.alerts:
        alertname = alert.labels.get("alertname", "unknown")
        cluster = alert.labels.get("cluster", "unknown")
        namespace = alert.labels.get("namespace")
        severity_str = alert.labels.get("severity", "warning")

        # Map severity
        try:
            severity = AlertSeverity(severity_str)
        except ValueError:
            severity = AlertSeverity.WARNING

        # Track metric
        alerts_received_total.labels(
            cluster=cluster, severity=severity.value
        ).inc()

        # Deduplication
        should_investigate, group_key = deduplicator.should_investigate(
            alertname, cluster, namespace
        )

        if not should_investigate:
            alerts_deduplicated_total.inc()
            deduplicated += 1
            logger.info(
                "alert_deduplicated",
                alertname=alertname,
                cluster=cluster,
                namespace=namespace,
                group_key=group_key,
            )
            continue

        # Enrichment
        enrich_start = time.time()
        enrichment = await enrich_alert(alertname, cluster, namespace, alert.labels)
        alert_enrichment_duration_seconds.observe(time.time() - enrich_start)

        # Create enriched alert
        enriched = EnrichedAlert(
            alertname=alertname,
            cluster=cluster,
            namespace=namespace,
            severity=severity,
            status=AlertStatus.FIRING,
            labels=alert.labels,
            annotations=alert.annotations,
            fingerprint=alert.fingerprint,
            enrichment_data=enrichment,
            dedup_group=group_key,
        )

        # Route to agent
        target = route_alert(alertname, alert.labels)

        # Mark as investigating
        deduplicator.mark_investigated(group_key)

        logger.info(
            "alert_routed",
            alert_id=str(enriched.alert_id),
            alertname=alertname,
            cluster=cluster,
            namespace=namespace,
            severity=severity.value,
            target=target.value,
        )

        processed.append({
            "alert_id": str(enriched.alert_id),
            "alertname": alertname,
            "cluster": cluster,
            "target_agent": target.value,
            "status": "investigating",
        })

    return {
        "status": "ok",
        "processed": len(processed),
        "deduplicated": deduplicated,
        "alerts": processed,
    }


@app.get("/api/v1/alerts/groups")
async def get_alert_groups():
    """Get current alert dedup group statistics."""
    return deduplicator.get_group_stats()
