"""Unit tests for SREAnalytics lifecycle hooks.

Uses a mock ClickHouseAnalyticsClient so no real ClickHouse is required.
Run with: pytest ai-sre/analytics/test_tracker.py -v
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Any
from unittest.mock import AsyncMock, MagicMock

import pytest

from .tracker import SREAnalytics, _compute_cost


# ── fixtures ─────────────────────────────────────────────────────────────────

class _FakeClient:
    """Records all write calls for assertion."""

    def __init__(self) -> None:
        self.agent_usage_rows: list[dict[str, Any]] = []
        self.finding_rows: list[dict[str, Any]] = []
        self.feedback_rows: list[dict[str, Any]] = []
        self.tool_call_rows: list[dict[str, Any]] = []

    async def write_agent_usage(self, row: dict[str, Any]) -> None:
        self.agent_usage_rows.append(row)

    async def write_finding(self, row: dict[str, Any]) -> None:
        self.finding_rows.append(row)

    async def write_feedback(self, row: dict[str, Any]) -> None:
        self.feedback_rows.append(row)

    async def write_tool_call(self, row: dict[str, Any]) -> None:
        self.tool_call_rows.append(row)


@pytest.fixture
def client() -> _FakeClient:
    return _FakeClient()


@pytest.fixture
def analytics(client: _FakeClient) -> SREAnalytics:
    return SREAnalytics(client)  # type: ignore[arg-type]


# ── cost computation ──────────────────────────────────────────────────────────

def test_cost_opus() -> None:
    # 1M input + 1M output at Opus pricing = $15 + $75 = $90
    cost = _compute_cost(
        "claude-opus-4-20250514",
        {"input": 1_000_000, "output": 1_000_000, "thinking": 0},
    )
    assert abs(cost - 90.0) < 0.001


def test_cost_sonnet() -> None:
    # 1M input + 1M output at Sonnet pricing = $3 + $15 = $18
    cost = _compute_cost(
        "claude-sonnet-4-20250514",
        {"input": 1_000_000, "output": 1_000_000, "thinking": 0},
    )
    assert abs(cost - 18.0) < 0.001


def test_cost_with_thinking() -> None:
    cost = _compute_cost(
        "claude-opus-4-20250514",
        {"input": 0, "output": 0, "thinking": 1_000_000},
    )
    assert abs(cost - 15.0) < 0.001


def test_cost_unknown_model_falls_back_to_default() -> None:
    cost = _compute_cost(
        "some-future-model",
        {"input": 1_000_000, "output": 0},
    )
    # Default input pricing = $3/M
    assert abs(cost - 3.0) < 0.001


# ── agent_start / on_tool_call / on_agent_complete ───────────────────────────

@pytest.mark.asyncio
async def test_full_invocation_lifecycle(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    inv_id = str(uuid.uuid4())

    analytics.on_agent_start(
        inv_id, "incident_response", "alert", "KubePodCrash",
        "prod-us-east-1", "default",
    )

    await analytics.on_tool_call(
        inv_id, "get_pod_logs", "k8s-mcp", 350, True,
        result_size_bytes=2048,
    )
    await analytics.on_tool_call(
        inv_id, "query_metrics", "metrics-mcp", 120, True,
        result_size_bytes=512,
    )

    await analytics.on_agent_complete(
        inv_id=inv_id,
        outcome="advisory_generated",
        model="claude-sonnet-4-20250514",
        agent_role="incident_response",
        cluster="prod-us-east-1",
        tokens={"input": 4000, "output": 800, "thinking": 0},
        duration_ms=45_000,
    )

    assert len(client.tool_call_rows) == 2
    assert len(client.agent_usage_rows) == 1
    assert len(client.finding_rows) == 0  # no finding passed

    usage = client.agent_usage_rows[0]
    assert usage["outcome"] == "advisory_generated"
    assert usage["tool_calls_count"] == 2
    assert "k8s-mcp" in usage["mcp_servers_used"]
    assert "metrics-mcp" in usage["mcp_servers_used"]
    assert usage["cost_usd"] > 0
    assert usage["tokens_input"] == 4000
    assert usage["tokens_output"] == 800


@pytest.mark.asyncio
async def test_finding_is_written_when_provided(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    inv_id = str(uuid.uuid4())
    finding_id = str(uuid.uuid4())

    analytics.on_agent_start(inv_id, "gpu_health", "alert", "DCGMGPUError", "gpu-prod", "")

    finding = {
        "finding_id": finding_id,
        "finding_type": "gpu_degradation",
        "severity": "high",
        "category": "hardware",
        "affected_resource": "gpu-node-01",
        "affected_resource_type": "node",
        "root_cause_summary": "GPU memory errors exceeding threshold",
        "confidence": "high",
        "recommendations": ["Cordon node", "Run DCGM diagnostic"],
        "evidence_sources": ["metrics", "events"],
        "time_to_advise_sec": 30.0,
    }

    await analytics.on_agent_complete(
        inv_id=inv_id,
        outcome="advisory_generated",
        model="claude-opus-4-20250514",
        agent_role="gpu_health",
        cluster="gpu-prod",
        tokens={"input": 8000, "output": 1500, "thinking": 5000},
        duration_ms=60_000,
        finding=finding,
    )

    assert len(client.finding_rows) == 1
    assert len(client.agent_usage_rows) == 1

    f = client.finding_rows[0]
    assert f["finding_id"] == finding_id
    assert f["finding_type"] == "gpu_degradation"
    assert f["severity"] == "high"
    assert f["status"] == "open"

    u = client.agent_usage_rows[0]
    assert u["finding_id"] == finding_id


@pytest.mark.asyncio
async def test_feedback_recording(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    finding_id = str(uuid.uuid4())
    inv_id = str(uuid.uuid4())

    await analytics.on_feedback(
        finding_id=finding_id,
        invocation_id=inv_id,
        agent_role="incident_response",
        cluster="prod-us-east-1",
        feedback_type="reaction",
        feedback_value="correct_rca",
        feedback_by="U123456",
    )

    assert len(client.feedback_rows) == 1
    fb = client.feedback_rows[0]
    assert fb["feedback_value"] == "correct_rca"
    assert fb["feedback_by"] == "U123456"


@pytest.mark.asyncio
async def test_resolution_writes_feedback_button(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    finding_id = str(uuid.uuid4())
    inv_id = str(uuid.uuid4())

    await analytics.on_resolution(
        finding_id=finding_id,
        invocation_id=inv_id,
        agent_role="cost_optimization",
        cluster="prod-eu-west-1",
        resolution_type="manual_fix",
        resolved_by="U789",
    )

    assert len(client.feedback_rows) == 1
    fb = client.feedback_rows[0]
    assert fb["feedback_type"] == "button"
    assert fb["feedback_value"] == "resolved"


@pytest.mark.asyncio
async def test_false_positive_resolution(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    finding_id = str(uuid.uuid4())
    inv_id = str(uuid.uuid4())

    await analytics.on_resolution(
        finding_id=finding_id,
        invocation_id=inv_id,
        agent_role="gpu_health",
        cluster="gpu-prod",
        resolution_type="false_positive",
        resolved_by="U001",
    )

    fb = client.feedback_rows[0]
    assert fb["feedback_value"] == "false_positive"


@pytest.mark.asyncio
async def test_invocation_state_cleared_after_complete(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    """Active invocations dict must not grow unbounded."""
    inv_id = str(uuid.uuid4())

    analytics.on_agent_start(inv_id, "scaling", "scheduled", "weekly_review", "staging", "")
    assert inv_id in analytics._active

    await analytics.on_agent_complete(
        inv_id=inv_id,
        outcome="no_action",
        model="claude-sonnet-4-20250514",
        agent_role="scaling",
        cluster="staging",
        tokens={"input": 1000, "output": 200},
        duration_ms=5000,
    )

    assert inv_id not in analytics._active


@pytest.mark.asyncio
async def test_unknown_invocation_complete_is_safe(
    analytics: SREAnalytics, client: _FakeClient
) -> None:
    """on_agent_complete should not raise when invocation_id is unknown."""
    await analytics.on_agent_complete(
        inv_id="no-such-id",
        outcome="error",
        model="claude-sonnet-4-20250514",
        agent_role="incident_response",
        cluster="unknown",
        tokens={"input": 0, "output": 0},
        duration_ms=0,
        error_message="agent timed out",
    )
    assert len(client.agent_usage_rows) == 1
    assert client.agent_usage_rows[0]["trigger_type"] == "unknown"
