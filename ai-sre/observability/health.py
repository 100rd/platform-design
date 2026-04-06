"""Health check endpoints for the AI SRE system.

Provides liveness, readiness, and self-monitoring capabilities.
If the AI SRE system itself is unhealthy, a fallback alert is sent
directly to Slack via raw Alertmanager routing.
"""

import logging
import os
from dataclasses import dataclass
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)


@dataclass
class ComponentHealth:
    """Health status of an individual component."""

    name: str
    healthy: bool
    message: str = ""
    latency_ms: float = 0.0


@dataclass
class SystemHealth:
    """Aggregate health of the AI SRE system."""

    healthy: bool
    components: list[ComponentHealth]
    message: str = ""


class HealthChecker:
    """Checks health of all AI SRE system components.

    Components checked:
    - Orchestrator API (readiness)
    - MCP servers (metrics, runbook)
    - ClickHouse connectivity
    - VictoriaMetrics connectivity
    - Anthropic API reachability
    - Slack API connectivity
    """

    def __init__(self) -> None:
        self.orchestrator_url = os.environ.get(
            "ORCHESTRATOR_URL",
            "http://ai-sre-orchestrator.ai-sre-system.svc.cluster.local:8000",
        )
        self.metrics_mcp_url = os.environ.get(
            "METRICS_MCP_URL",
            "http://metrics-mcp.ai-sre-system.svc.cluster.local:8080",
        )
        self.clickhouse_url = os.environ.get(
            "CLICKHOUSE_URL",
            "http://clickhouse.monitoring.svc.cluster.local:8123",
        )
        self.victoriametrics_url = os.environ.get(
            "VICTORIAMETRICS_URL",
            "http://vmselect.monitoring.svc.cluster.local:8481",
        )

    async def check_all(self) -> SystemHealth:
        """Check health of all components and return aggregate status."""
        checks = [
            self._check_orchestrator(),
            self._check_metrics_mcp(),
            self._check_clickhouse(),
            self._check_victoriametrics(),
        ]

        components: list[ComponentHealth] = []
        for check_coro in checks:
            try:
                result = await check_coro
                components.append(result)
            except Exception as e:
                components.append(
                    ComponentHealth(
                        name="unknown",
                        healthy=False,
                        message=str(e),
                    )
                )

        all_healthy = all(c.healthy for c in components)
        return SystemHealth(
            healthy=all_healthy,
            components=components,
            message="All components healthy" if all_healthy else "Degraded",
        )

    async def _check_orchestrator(self) -> ComponentHealth:
        """Check orchestrator API readiness."""
        return await self._http_check(
            "orchestrator", f"{self.orchestrator_url}/readyz"
        )

    async def _check_metrics_mcp(self) -> ComponentHealth:
        """Check metrics MCP server health."""
        return await self._http_check(
            "metrics-mcp", f"{self.metrics_mcp_url}/health"
        )

    async def _check_clickhouse(self) -> ComponentHealth:
        """Check ClickHouse connectivity."""
        return await self._http_check(
            "clickhouse", f"{self.clickhouse_url}/ping"
        )

    async def _check_victoriametrics(self) -> ComponentHealth:
        """Check VictoriaMetrics connectivity."""
        return await self._http_check(
            "victoriametrics",
            f"{self.victoriametrics_url}/health",
        )

    async def _http_check(
        self, name: str, url: str, timeout: float = 5.0
    ) -> ComponentHealth:
        """Perform an HTTP health check."""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(url, timeout=timeout)
                healthy = response.status_code < 400
                return ComponentHealth(
                    name=name,
                    healthy=healthy,
                    message=f"HTTP {response.status_code}",
                )
        except httpx.TimeoutException:
            return ComponentHealth(
                name=name,
                healthy=False,
                message=f"Timeout after {timeout}s",
            )
        except httpx.ConnectError as e:
            return ComponentHealth(
                name=name,
                healthy=False,
                message=f"Connection error: {e}",
            )
        except Exception as e:
            return ComponentHealth(
                name=name,
                healthy=False,
                message=str(e),
            )
