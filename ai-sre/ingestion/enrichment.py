"""Alert enrichment — adds context to raw alerts before agent processing."""

import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)

# Service URLs (configured via environment)
VICTORIAMETRICS_URL = "http://vmselect.monitoring.svc.cluster.local:8481"
CLICKHOUSE_URL = "http://clickhouse.monitoring.svc.cluster.local:8123"


async def enrich_with_resource_utilization(
    cluster: str, namespace: str | None
) -> dict[str, Any]:
    """Fetch current resource utilization from VictoriaMetrics."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            queries = {}
            if namespace:
                queries["cpu_usage"] = (
                    f'sum(rate(container_cpu_usage_seconds_total'
                    f'{{namespace="{namespace}", cluster="{cluster}"}}[5m]))'
                )
                queries["memory_usage"] = (
                    f'sum(container_memory_working_set_bytes'
                    f'{{namespace="{namespace}", cluster="{cluster}"}})'
                )
            results = {}
            for name, promql in queries.items():
                resp = await client.get(
                    f"{VICTORIAMETRICS_URL}/select/0/prometheus/api/v1/query",
                    params={"query": promql},
                )
                if resp.status_code == 200:
                    results[name] = resp.json()
            return results
    except Exception as e:
        logger.warning("Failed to enrich resource utilization: %s", e)
        return {}


async def enrich_with_recent_alerts(
    alertname: str, cluster: str
) -> list[dict[str, Any]]:
    """Fetch recent similar alerts from ClickHouse history."""
    try:
        sql = (
            "SELECT alert_id, timestamp, alertname, status, agent_advisory "
            "FROM ai_sre.alerts "
            f"WHERE alertname = '{alertname}' AND cluster = '{cluster}' "
            "AND timestamp > now() - INTERVAL 7 DAY "
            "ORDER BY timestamp DESC LIMIT 5 FORMAT JSON"
        )
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(CLICKHOUSE_URL, content=sql)
            if resp.status_code == 200:
                data = resp.json()
                return data.get("data", [])
    except Exception as e:
        logger.warning("Failed to fetch recent alerts: %s", e)
    return []


async def enrich_alert(
    alertname: str,
    cluster: str,
    namespace: str | None,
    labels: dict[str, str],
) -> dict[str, Any]:
    """Enrich an alert with all available context.

    Gathers:
    - Current resource utilization from VictoriaMetrics
    - Recent similar alerts from ClickHouse
    - Affected cluster and namespace metadata
    """
    enrichment: dict[str, Any] = {
        "cluster": cluster,
        "namespace": namespace,
    }

    # Resource utilization
    utilization = await enrich_with_resource_utilization(cluster, namespace)
    if utilization:
        enrichment["resource_utilization"] = utilization

    # Recent similar alerts
    recent = await enrich_with_recent_alerts(alertname, cluster)
    if recent:
        enrichment["recent_similar_alerts"] = recent
        enrichment["recent_similar_count"] = len(recent)

    return enrichment
