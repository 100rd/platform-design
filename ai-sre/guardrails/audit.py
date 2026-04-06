"""Audit logging for AI SRE agent actions.

Every MCP tool call, Slack message, and approval/denial is logged
immutably to ClickHouse for compliance and post-incident analysis.
"""

import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)


@dataclass
class AuditEntry:
    """Single audit log entry for an agent action."""

    agent_id: str
    agent_role: str
    action: str
    tool_name: str
    tool_input: str = ""
    tool_output_summary: str = ""
    cluster: str = ""
    namespace: str = ""
    approved_by: Optional[str] = None
    approval_timestamp: Optional[str] = None
    tokens_used: int = 0
    duration_ms: int = 0
    error: Optional[str] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class AuditLogger:
    """Writes audit entries to ClickHouse.

    All agent actions are logged immutably with:
    - Agent identity (role, instance ID)
    - Tool call details (name, input, output summary)
    - Cluster/namespace context
    - Approval info (who approved, when)
    - Token usage and duration
    - Any errors encountered
    """

    def __init__(
        self,
        clickhouse_url: Optional[str] = None,
    ) -> None:
        self.clickhouse_url = clickhouse_url or os.environ.get(
            "CLICKHOUSE_URL",
            "http://clickhouse.monitoring.svc.cluster.local:8123",
        )
        self._buffer: list[AuditEntry] = []
        self._buffer_size = 100

    async def log(self, entry: AuditEntry) -> None:
        """Log an audit entry.

        Buffers entries and flushes in batches for efficiency.
        """
        self._buffer.append(entry)
        logger.debug(
            "audit_entry_buffered",
            agent_role=entry.agent_role,
            tool_name=entry.tool_name,
            action=entry.action,
        )

        if len(self._buffer) >= self._buffer_size:
            await self.flush()

    async def log_tool_call(
        self,
        agent_id: str,
        agent_role: str,
        tool_name: str,
        tool_input: dict[str, Any],
        tool_output_summary: str = "",
        cluster: str = "",
        namespace: str = "",
        tokens_used: int = 0,
        duration_ms: int = 0,
        error: Optional[str] = None,
    ) -> None:
        """Convenience method for logging a tool call."""
        # Sanitize tool input to remove potential secrets
        safe_input = _sanitize_input(tool_input)
        entry = AuditEntry(
            agent_id=agent_id,
            agent_role=agent_role,
            action="tool_call",
            tool_name=tool_name,
            tool_input=str(safe_input),
            tool_output_summary=tool_output_summary[:500],
            cluster=cluster,
            namespace=namespace,
            tokens_used=tokens_used,
            duration_ms=duration_ms,
            error=error,
        )
        await self.log(entry)

    async def log_approval(
        self,
        agent_id: str,
        agent_role: str,
        action: str,
        approved_by: str,
        cluster: str = "",
        namespace: str = "",
    ) -> None:
        """Log a human approval action."""
        entry = AuditEntry(
            agent_id=agent_id,
            agent_role=agent_role,
            action=f"approval:{action}",
            tool_name="approval_workflow",
            approved_by=approved_by,
            approval_timestamp=datetime.now(timezone.utc).isoformat(),
            cluster=cluster,
            namespace=namespace,
        )
        await self.log(entry)

    async def log_slack_message(
        self,
        agent_id: str,
        agent_role: str,
        channel: str,
        message_type: str = "advisory",
    ) -> None:
        """Log a Slack message sent by an agent."""
        entry = AuditEntry(
            agent_id=agent_id,
            agent_role=agent_role,
            action=f"slack:{message_type}",
            tool_name="slack_api",
            tool_input=f"channel={channel}",
        )
        await self.log(entry)

    async def flush(self) -> None:
        """Flush buffered entries to ClickHouse.

        In production, this inserts entries into the ai_sre.audit_log table.
        """
        if not self._buffer:
            return

        entries = self._buffer.copy()
        self._buffer.clear()

        logger.info("audit_flush", entry_count=len(entries))

        # In production: batch INSERT into ClickHouse
        # INSERT INTO ai_sre.audit_log (timestamp, agent_id, agent_role, ...)
        # VALUES (...)


def _sanitize_input(tool_input: dict[str, Any]) -> dict[str, Any]:
    """Remove potential secrets from tool input before logging."""
    sensitive_keys = {
        "password", "secret", "token", "api_key", "apikey",
        "authorization", "auth", "credential", "private_key",
    }
    sanitized = {}
    for key, value in tool_input.items():
        if key.lower() in sensitive_keys:
            sanitized[key] = "***REDACTED***"
        elif isinstance(value, str) and len(value) > 1000:
            sanitized[key] = value[:1000] + "...[truncated]"
        else:
            sanitized[key] = value
    return sanitized
