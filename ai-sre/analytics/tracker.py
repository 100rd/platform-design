"""SREAnalytics — lifecycle hooks that wrap every agent invocation.

Designed to slot into the Claude Agent SDK event callbacks without ever
blocking the investigation loop.  All writes go through the async-buffered
ClickHouseAnalyticsClient.

Typical integration inside an agent runner:

    analytics = SREAnalytics(ch_client)
    inv_id = str(uuid.uuid4())

    analytics.on_agent_start(inv_id, "incident_response", trigger, ctx)

    for tool_name, server, duration, ok in tool_events:
        await analytics.on_tool_call(inv_id, tool_name, server, duration, ok)

    await analytics.on_agent_complete(
        inv_id,
        outcome="advisory_generated",
        model="claude-opus-4-20250514",
        agent_role="incident_response",
        cluster="prod-us-east-1",
        tokens={"input": 4000, "output": 800, "thinking": 3200},
        duration_ms=45_000,
        finding=finding_dict,   # or None
    )
"""

from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from .client import ClickHouseAnalyticsClient

logger = logging.getLogger(__name__)

# Anthropic pricing (USD per million tokens, as of Claude 4)
_MODEL_PRICING: dict[str, dict[str, float]] = {
    "claude-opus-4-20250514": {"input": 15.0, "output": 75.0, "thinking": 15.0},
    "claude-sonnet-4-20250514": {"input": 3.0, "output": 15.0, "thinking": 3.0},
}
_DEFAULT_PRICING = {"input": 3.0, "output": 15.0, "thinking": 3.0}


@dataclass
class _InvocationState:
    """Transient in-memory state for one agent invocation."""

    invocation_id: str
    agent_role: str
    trigger_type: str
    trigger_source: str
    cluster: str
    namespace: str
    started_at: float = field(default_factory=time.monotonic)
    started_wall: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    tool_events: list[dict[str, Any]] = field(default_factory=list)
    mcp_servers: set[str] = field(default_factory=set)


class SREAnalytics:
    """Agent SDK lifecycle hooks — usage, findings, tool calls, and feedback.

    All methods are safe to call from async contexts; they schedule writes
    to the ClickHouse client's internal buffer and return immediately.
    """

    def __init__(self, ch_client: ClickHouseAnalyticsClient) -> None:
        self._ch = ch_client
        self._active: dict[str, _InvocationState] = {}

    # ── lifecycle hooks ──────────────────────────────────────────────────────

    def on_agent_start(
        self,
        invocation_id: str,
        agent_role: str,
        trigger_type: str,
        trigger_source: str,
        cluster: str,
        namespace: str = "",
    ) -> None:
        """Called when an investigation begins.

        Records the start wall-clock time and sets up per-invocation state.
        This is a synchronous method — it does no I/O.
        """
        state = _InvocationState(
            invocation_id=invocation_id,
            agent_role=agent_role,
            trigger_type=trigger_type,
            trigger_source=trigger_source,
            cluster=cluster,
            namespace=namespace,
        )
        self._active[invocation_id] = state
        logger.debug(
            "analytics_agent_start",
            invocation_id=invocation_id,
            agent_role=agent_role,
        )

    async def on_tool_call(
        self,
        invocation_id: str,
        tool_name: str,
        mcp_server: str,
        duration_ms: int,
        success: bool,
        error_message: Optional[str] = None,
        result_size_bytes: int = 0,
    ) -> None:
        """Called after each MCP tool call completes."""
        state = self._active.get(invocation_id)
        if state:
            state.mcp_servers.add(mcp_server)
            state.tool_events.append(
                {"tool_name": tool_name, "mcp_server": mcp_server}
            )

        await self._ch.write_tool_call(
            {
                "invocation_id": invocation_id,
                "agent_role": (state.agent_role if state else "unknown"),
                "tool_name": tool_name,
                "mcp_server": mcp_server,
                "duration_ms": duration_ms,
                "success": success,
                "error_message": error_message,
                "result_size_bytes": result_size_bytes,
            }
        )

    async def on_agent_complete(
        self,
        invocation_id: str,
        outcome: str,
        model: str,
        agent_role: str,
        cluster: str,
        tokens: dict[str, int],
        duration_ms: int,
        finding: Optional[dict[str, Any]] = None,
        error_message: Optional[str] = None,
        namespace: str = "",
    ) -> None:
        """Called when an investigation finishes.

        Writes the agent_usage row and, if a finding was produced, the
        findings row.  The finding dict should conform to the findings
        table schema (minus finding_id and timestamp which are injected
        here if missing).
        """
        state = self._active.pop(invocation_id, None)
        finding_id: Optional[str] = None

        cost = _compute_cost(model, tokens)

        # Persist finding first so we can reference its ID in agent_usage
        if finding is not None:
            finding_id = finding.get("finding_id") or str(uuid.uuid4())
            finding_row: dict[str, Any] = {
                "finding_id": finding_id,
                "invocation_id": invocation_id,
                "agent_role": agent_role,
                "cluster": cluster,
                "namespace": namespace,
                # Callers must supply finding_type, severity, etc.
                **finding,
            }
            finding_row.setdefault("status", "open")
            finding_row.setdefault("k8s_signals_count", 0)
            finding_row.setdefault("aws_signals_count", 0)
            finding_row.setdefault("is_cross_layer", False)
            finding_row.setdefault(
                "agent_started_at",
                state.started_wall if state else datetime.now(timezone.utc).isoformat(),
            )
            finding_row.setdefault(
                "advisory_posted_at", datetime.now(timezone.utc).isoformat()
            )
            finding_row.setdefault("time_to_advise_sec", duration_ms / 1000.0)
            await self._ch.write_finding(finding_row)

        mcp_servers = list(state.mcp_servers) if state else []
        tools_used = (
            list({e["tool_name"] for e in state.tool_events}) if state else []
        )
        trigger_type = state.trigger_type if state else "unknown"
        trigger_source = state.trigger_source if state else ""

        await self._ch.write_agent_usage(
            {
                "invocation_id": invocation_id,
                "agent_role": agent_role,
                "model": model,
                "trigger_type": trigger_type,
                "trigger_source": trigger_source,
                "cluster": cluster,
                "namespace": namespace,
                "duration_ms": duration_ms,
                "tokens_input": tokens.get("input", 0),
                "tokens_output": tokens.get("output", 0),
                "tokens_thinking": tokens.get("thinking", 0),
                "cost_usd": cost,
                "tool_calls_count": len(state.tool_events) if state else 0,
                "mcp_servers_used": mcp_servers,
                "tools_used": tools_used,
                "outcome": outcome,
                "error_message": error_message,
                "finding_id": finding_id,
            }
        )

        logger.info(
            "analytics_agent_complete",
            invocation_id=invocation_id,
            agent_role=agent_role,
            outcome=outcome,
            cost_usd=f"${cost:.4f}",
        )

    async def on_feedback(
        self,
        finding_id: str,
        invocation_id: str,
        agent_role: str,
        cluster: str,
        feedback_type: str,
        feedback_value: str,
        feedback_by: str,
        feedback_comment: Optional[str] = None,
    ) -> None:
        """Called when a human reacts to an advisory in Slack."""
        await self._ch.write_feedback(
            {
                "finding_id": finding_id,
                "invocation_id": invocation_id,
                "feedback_type": feedback_type,
                "feedback_value": feedback_value,
                "feedback_by": feedback_by,
                "feedback_comment": feedback_comment,
                "agent_role": agent_role,
                "cluster": cluster,
            }
        )

    async def on_resolution(
        self,
        finding_id: str,
        invocation_id: str,
        agent_role: str,
        cluster: str,
        resolution_type: str,
        resolved_by: str,
        feedback_comment: Optional[str] = None,
    ) -> None:
        """Called when a finding is marked resolved or false positive via Slack.

        Writes a feedback row with feedback_type='button' so resolution events
        are captured alongside reaction-based feedback for accuracy reporting.
        """
        feedback_value = (
            "false_positive"
            if resolution_type == "false_positive"
            else "resolved"
        )
        await self._ch.write_feedback(
            {
                "finding_id": finding_id,
                "invocation_id": invocation_id,
                "feedback_type": "button",
                "feedback_value": feedback_value,
                "feedback_by": resolved_by,
                "feedback_comment": feedback_comment,
                "agent_role": agent_role,
                "cluster": cluster,
            }
        )


# ── helpers ──────────────────────────────────────────────────────────────────

def _compute_cost(model: str, tokens: dict[str, int]) -> float:
    pricing = _MODEL_PRICING.get(model, _DEFAULT_PRICING)
    return (
        tokens.get("input", 0) * pricing["input"] / 1_000_000
        + tokens.get("output", 0) * pricing["output"] / 1_000_000
        + tokens.get("thinking", 0) * pricing.get("thinking", pricing["input"]) / 1_000_000
    )
