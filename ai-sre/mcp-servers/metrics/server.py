"""Metrics MCP Server — PromQL/MetricsQL queries against VictoriaMetrics + ClickHouse SQL."""

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

logger = logging.getLogger(__name__)

# Configuration
VM_URL = os.environ.get("VICTORIAMETRICS_URL", "http://vmselect.monitoring.svc.cluster.local:8481")
CH_URL = os.environ.get("CLICKHOUSE_URL", "http://clickhouse.monitoring.svc.cluster.local:8123")
CH_DATABASE = os.environ.get("CLICKHOUSE_DATABASE", "default")
QUERY_TIMEOUT = int(os.environ.get("QUERY_TIMEOUT_SECONDS", "30"))
MAX_RESULT_ROWS = int(os.environ.get("MAX_RESULT_ROWS", "10000"))

# Blocked patterns for ClickHouse safety
BLOCKED_CH_PATTERNS = [
    "INSERT", "DELETE", "ALTER", "DROP", "CREATE", "TRUNCATE",
    "RENAME", "GRANT", "REVOKE", "ATTACH", "DETACH",
    "system.", "SYSTEM ",
]


@dataclass
class QueryTemplate:
    """Pre-built query template for common SRE queries."""

    name: str
    description: str
    query: str
    query_type: str  # "promql" or "sql"
    parameters: list[str]


# Pre-built query templates for common SRE patterns
QUERY_TEMPLATES: dict[str, QueryTemplate] = {
    "gpu_utilization": QueryTemplate(
        name="gpu_utilization",
        description="GPU utilization by node and namespace",
        query='DCGM_FI_DEV_GPU_UTIL{{kubernetes_node=~"{node}", namespace=~"{namespace}"}}',
        query_type="promql",
        parameters=["node", "namespace"],
    ),
    "pod_restart_rate": QueryTemplate(
        name="pod_restart_rate",
        description="Pod restart rate by namespace",
        query='rate(kube_pod_container_status_restarts_total{{namespace="{namespace}"}}[{window}])',
        query_type="promql",
        parameters=["namespace", "window"],
    ),
    "apiserver_latency": QueryTemplate(
        name="apiserver_latency",
        description="API server request latency percentiles",
        query=(
            "histogram_quantile({percentile}, "
            'rate(apiserver_request_duration_seconds_bucket{{cluster="{cluster}"}}[{window}]))'
        ),
        query_type="promql",
        parameters=["cluster", "percentile", "window"],
    ),
    "network_errors": QueryTemplate(
        name="network_errors",
        description="Cilium network error rates",
        query='rate(cilium_drop_count_total{{reason!="Policy denied"}}[{window}])',
        query_type="promql",
        parameters=["window"],
    ),
    "nccl_throughput": QueryTemplate(
        name="nccl_throughput",
        description="NCCL training throughput",
        query='DCGM_FI_PROF_NVLINK_TX_BYTES{{namespace="{namespace}"}}',
        query_type="promql",
        parameters=["namespace"],
    ),
    "vllm_queue_depth": QueryTemplate(
        name="vllm_queue_depth",
        description="vLLM inference request queue depth",
        query='vllm_num_requests_waiting{{namespace="{namespace}"}}',
        query_type="promql",
        parameters=["namespace"],
    ),
    "node_pressure": QueryTemplate(
        name="node_pressure",
        description="Node disk and memory pressure",
        query=(
            'kube_node_status_condition{{condition=~"DiskPressure|MemoryPressure", '
            'status="true", node=~"{node}"}}'
        ),
        query_type="promql",
        parameters=["node"],
    ),
}


def validate_clickhouse_query(sql: str) -> bool:
    """Validate that a ClickHouse query is read-only and safe."""
    upper_sql = sql.upper().strip()
    for pattern in BLOCKED_CH_PATTERNS:
        if pattern.upper() in upper_sql:
            return False
    # Must start with SELECT or WITH
    if not (upper_sql.startswith("SELECT") or upper_sql.startswith("WITH")):
        return False
    return True


async def query_victoriametrics(
    promql: str,
    start: str,
    end: str,
    step: str,
) -> dict[str, Any]:
    """Execute a PromQL/MetricsQL range query against VictoriaMetrics."""
    async with httpx.AsyncClient(timeout=QUERY_TIMEOUT) as client:
        response = await client.get(
            f"{VM_URL}/select/0/prometheus/api/v1/query_range",
            params={
                "query": promql,
                "start": start,
                "end": end,
                "step": step,
            },
        )
        response.raise_for_status()
        return response.json()


async def query_clickhouse(sql: str, limit: int = 100) -> dict[str, Any]:
    """Execute a read-only SQL query against ClickHouse."""
    if not validate_clickhouse_query(sql):
        raise ValueError("Query blocked: only SELECT/WITH statements allowed, system tables excluded")

    effective_limit = min(limit, MAX_RESULT_ROWS)
    # Append LIMIT if not already present
    if "LIMIT" not in sql.upper():
        sql = f"{sql} LIMIT {effective_limit}"

    async with httpx.AsyncClient(timeout=QUERY_TIMEOUT) as client:
        response = await client.post(
            CH_URL,
            params={"database": CH_DATABASE},
            content=f"{sql} FORMAT JSON",
            headers={"Content-Type": "text/plain"},
        )
        response.raise_for_status()
        return response.json()


# MCP Server definition
server = Server("metrics-mcp")


@server.list_tools()
async def list_tools() -> list[Tool]:
    """List available metrics tools."""
    return [
        Tool(
            name="query_metrics",
            description=(
                "Execute a PromQL/MetricsQL range query against VictoriaMetrics. "
                "Returns time series data."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "promql": {"type": "string", "description": "PromQL/MetricsQL query"},
                    "start": {
                        "type": "string",
                        "description": "Start time (RFC3339 or relative like -1h)",
                    },
                    "end": {
                        "type": "string",
                        "description": "End time (RFC3339 or relative like now)",
                    },
                    "step": {
                        "type": "string",
                        "description": "Query resolution step (e.g., 15s, 1m, 5m)",
                    },
                },
                "required": ["promql", "start", "end", "step"],
            },
        ),
        Tool(
            name="query_logs",
            description=(
                "Execute a read-only SQL query against ClickHouse logs. "
                "Only SELECT statements allowed. System tables blocked."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "sql": {"type": "string", "description": "SQL SELECT query"},
                    "limit": {
                        "type": "integer",
                        "description": "Max rows to return (default 100, max 10000)",
                        "default": 100,
                    },
                },
                "required": ["sql"],
            },
        ),
        Tool(
            name="get_gpu_health",
            description="Get GPU health report for a cluster/node using DCGM metrics.",
            inputSchema={
                "type": "object",
                "properties": {
                    "cluster": {"type": "string", "description": "Cluster name"},
                    "node": {
                        "type": "string",
                        "description": "Optional node name filter",
                    },
                },
                "required": ["cluster"],
            },
        ),
        Tool(
            name="get_cluster_capacity",
            description="Get cluster capacity report: CPU, memory, GPU allocation and usage.",
            inputSchema={
                "type": "object",
                "properties": {
                    "cluster": {"type": "string", "description": "Cluster name"},
                },
                "required": ["cluster"],
            },
        ),
        Tool(
            name="get_error_rate",
            description="Get error rate for a namespace over a time window.",
            inputSchema={
                "type": "object",
                "properties": {
                    "namespace": {"type": "string", "description": "Kubernetes namespace"},
                    "window": {
                        "type": "string",
                        "description": "Time window (e.g., 5m, 1h)",
                        "default": "5m",
                    },
                },
                "required": ["namespace"],
            },
        ),
        Tool(
            name="get_latency_percentiles",
            description="Get latency percentiles (p50, p95, p99) for a service.",
            inputSchema={
                "type": "object",
                "properties": {
                    "service": {"type": "string", "description": "Service name"},
                    "percentiles": {
                        "type": "array",
                        "items": {"type": "number"},
                        "description": "Percentiles to compute",
                        "default": [50, 95, 99],
                    },
                },
                "required": ["service"],
            },
        ),
        Tool(
            name="use_template",
            description="Execute a pre-built query template with parameters.",
            inputSchema={
                "type": "object",
                "properties": {
                    "template_name": {
                        "type": "string",
                        "description": "Template name",
                        "enum": list(QUERY_TEMPLATES.keys()),
                    },
                    "parameters": {
                        "type": "object",
                        "description": "Template parameter values",
                    },
                },
                "required": ["template_name", "parameters"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    """Execute a metrics tool call."""
    try:
        if name == "query_metrics":
            result = await query_victoriametrics(
                promql=arguments["promql"],
                start=arguments["start"],
                end=arguments["end"],
                step=arguments["step"],
            )
            return [TextContent(type="text", text=str(result))]

        elif name == "query_logs":
            result = await query_clickhouse(
                sql=arguments["sql"],
                limit=arguments.get("limit", 100),
            )
            return [TextContent(type="text", text=str(result))]

        elif name == "get_gpu_health":
            cluster = arguments["cluster"]
            node_filter = arguments.get("node", ".*")
            promql = (
                "{"
                f'DCGM_FI_DEV_GPU_UTIL{{kubernetes_node=~"{node_filter}", cluster="{cluster}"}}, '
                f'DCGM_FI_DEV_GPU_TEMP{{kubernetes_node=~"{node_filter}", cluster="{cluster}"}}, '
                f'DCGM_FI_DEV_ECC_DBE_VOL_TOTAL{{kubernetes_node=~"{node_filter}", cluster="{cluster}"}}'
                "}"
            )
            result = await query_victoriametrics(
                promql=f'DCGM_FI_DEV_GPU_UTIL{{kubernetes_node=~"{node_filter}", cluster="{cluster}"}}',
                start="-15m",
                end="now",
                step="1m",
            )
            return [TextContent(type="text", text=str(result))]

        elif name == "get_cluster_capacity":
            cluster = arguments["cluster"]
            result = await query_victoriametrics(
                promql=f'kube_node_status_allocatable{{cluster="{cluster}"}}',
                start="-5m",
                end="now",
                step="1m",
            )
            return [TextContent(type="text", text=str(result))]

        elif name == "get_error_rate":
            ns = arguments["namespace"]
            window = arguments.get("window", "5m")
            result = await query_victoriametrics(
                promql=f'sum(rate(container_network_receive_errors_total{{namespace="{ns}"}}[{window}]))',
                start=f"-{window}",
                end="now",
                step="1m",
            )
            return [TextContent(type="text", text=str(result))]

        elif name == "get_latency_percentiles":
            service = arguments["service"]
            percentiles = arguments.get("percentiles", [50, 95, 99])
            results = {}
            for p in percentiles:
                result = await query_victoriametrics(
                    promql=(
                        f"histogram_quantile({p / 100}, "
                        f'rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m]))'
                    ),
                    start="-15m",
                    end="now",
                    step="1m",
                )
                results[f"p{p}"] = result
            return [TextContent(type="text", text=str(results))]

        elif name == "use_template":
            template = QUERY_TEMPLATES.get(arguments["template_name"])
            if not template:
                return [TextContent(type="text", text=f"Unknown template: {arguments['template_name']}")]
            params = arguments.get("parameters", {})
            query = template.query.format(**params)
            if template.query_type == "promql":
                result = await query_victoriametrics(
                    promql=query, start="-1h", end="now", step="1m"
                )
            else:
                result = await query_clickhouse(sql=query)
            return [TextContent(type="text", text=str(result))]

        else:
            return [TextContent(type="text", text=f"Unknown tool: {name}")]

    except Exception as e:
        logger.error("Tool call failed: %s — %s", name, str(e))
        return [TextContent(type="text", text=f"Error: {str(e)}")]


async def main():
    """Run the Metrics MCP server."""
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream)


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
