"""ClickHouse client for the AI SRE analytics layer.

Manages connection pooling, async buffered writes, and schema migration.
All writes are fire-and-forget from the agent's perspective — errors are
logged but never propagate back to the caller, so analytics never blocks
an investigation.
"""

from __future__ import annotations

import asyncio
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any

import clickhouse_connect

logger = logging.getLogger(__name__)

# Batch parameters
_BATCH_SIZE = 100       # flush when buffer reaches this many rows
_FLUSH_INTERVAL = 10.0  # flush every N seconds regardless of size


class ClickHouseAnalyticsClient:
    """Async-safe, batched ClickHouse writer for AI SRE analytics.

    Usage
    -----
    client = ClickHouseAnalyticsClient.from_env()
    await client.start()          # launches background flush task
    ...
    await client.stop()           # drains remaining buffer
    """

    def __init__(
        self,
        host: str,
        port: int = 8123,
        username: str = "ai_sre",
        password: str = "",
        database: str = "ai_sre",
        batch_size: int = _BATCH_SIZE,
        flush_interval: float = _FLUSH_INTERVAL,
    ) -> None:
        self._host = host
        self._port = port
        self._username = username
        self._password = password
        self._database = database
        self._batch_size = batch_size
        self._flush_interval = flush_interval

        # Per-table write buffers
        self._buffers: dict[str, list[dict[str, Any]]] = {
            "agent_usage": [],
            "findings": [],
            "feedback": [],
            "tool_calls": [],
        }
        self._lock = asyncio.Lock()
        self._flush_task: asyncio.Task[None] | None = None
        self._ch: clickhouse_connect.driver.Client | None = None

    @classmethod
    def from_env(cls) -> "ClickHouseAnalyticsClient":
        """Construct from environment variables.

        Required env vars:
        - CLICKHOUSE_HOST
        - CLICKHOUSE_PORT       (default: 8123)
        - CLICKHOUSE_USER       (default: ai_sre)
        - CLICKHOUSE_PASSWORD
        """
        return cls(
            host=os.environ["CLICKHOUSE_HOST"],
            port=int(os.environ.get("CLICKHOUSE_PORT", "8123")),
            username=os.environ.get("CLICKHOUSE_USER", "ai_sre"),
            password=os.environ.get("CLICKHOUSE_PASSWORD", ""),
        )

    # ── lifecycle ────────────────────────────────────────────────────────────

    async def start(self) -> None:
        """Connect to ClickHouse and start the background flush loop."""
        loop = asyncio.get_event_loop()
        self._ch = await loop.run_in_executor(
            None,
            lambda: clickhouse_connect.get_client(
                host=self._host,
                port=self._port,
                username=self._username,
                password=self._password,
                database=self._database,
                connect_timeout=5,
                send_receive_timeout=30,
            ),
        )
        logger.info(
            "clickhouse_analytics_connected",
            host=self._host,
            database=self._database,
        )
        self._flush_task = asyncio.create_task(self._flush_loop())

    async def stop(self) -> None:
        """Stop the flush loop and drain all buffered rows."""
        if self._flush_task:
            self._flush_task.cancel()
            try:
                await self._flush_task
            except asyncio.CancelledError:
                pass
        await self._flush_all()

    # ── public write API ─────────────────────────────────────────────────────

    async def write_agent_usage(self, row: dict[str, Any]) -> None:
        """Buffer a single agent invocation row."""
        row.setdefault("invocation_id", str(uuid.uuid4()))
        row.setdefault("timestamp", _now())
        await self._buffer("agent_usage", row)

    async def write_finding(self, row: dict[str, Any]) -> None:
        """Buffer a single finding row."""
        row.setdefault("finding_id", str(uuid.uuid4()))
        row.setdefault("timestamp", _now())
        await self._buffer("findings", row)

    async def write_feedback(self, row: dict[str, Any]) -> None:
        """Buffer a feedback row from a Slack reaction or button click."""
        row.setdefault("timestamp", _now())
        await self._buffer("feedback", row)

    async def write_tool_call(self, row: dict[str, Any]) -> None:
        """Buffer a single MCP tool call row."""
        row.setdefault("timestamp", _now())
        await self._buffer("tool_calls", row)

    # ── internal ────────────────────────────────────────────────────────────

    async def _buffer(self, table: str, row: dict[str, Any]) -> None:
        async with self._lock:
            self._buffers[table].append(row)
            if len(self._buffers[table]) >= self._batch_size:
                await self._flush_table(table)

    async def _flush_loop(self) -> None:
        while True:
            await asyncio.sleep(self._flush_interval)
            await self._flush_all()

    async def _flush_all(self) -> None:
        for table in list(self._buffers.keys()):
            async with self._lock:
                if self._buffers[table]:
                    await self._flush_table(table)

    async def _flush_table(self, table: str) -> None:
        """Flush a table's buffer to ClickHouse (must be called under lock)."""
        rows = self._buffers[table]
        if not rows or self._ch is None:
            return
        self._buffers[table] = []

        try:
            loop = asyncio.get_event_loop()
            column_names = list(rows[0].keys())
            data = [[row.get(col) for col in column_names] for row in rows]
            await loop.run_in_executor(
                None,
                lambda: self._ch.insert(  # type: ignore[union-attr]
                    f"ai_sre.{table}",
                    data,
                    column_names=column_names,
                ),
            )
            logger.debug(
                "clickhouse_batch_flushed",
                table=table,
                rows=len(rows),
            )
        except Exception:
            logger.exception(
                "clickhouse_flush_failed",
                table=table,
                rows=len(rows),
            )
            # Put rows back so we don't lose them
            self._buffers[table] = rows + self._buffers[table]


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
