import sys
from pathlib import Path
import pytest

# Ensure the root of the project is in PYTHONPATH
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from guardrails.read_only import ToolCallGuard, get_guardrails


def test_allowed_read_operation():
    """Verify that a standard read operation is permitted."""
    guardrails = get_guardrails("gpu-health")
    guard = ToolCallGuard(guardrails)

    allowed, reason = guard.validate("list_pods")
    assert allowed is True
    assert reason == "allowed"


def test_blocked_write_operation():
    """Verify that write operations are blocked for read-only agents."""
    guardrails = get_guardrails("oncall-copilot")
    guard = ToolCallGuard(guardrails)

    # Cordon is a write verb
    allowed, reason = guard.validate("cordon_node")
    assert allowed is False
    assert "blocked for read-only agent" in reason


def test_tool_call_limit_exceeded():
    """Verify that exceeding the max tool call limit blocks execution."""
    guardrails = get_guardrails("predictive-scaling")
    # Artificially set a low limit for testing
    guardrails.max_tool_calls = 2

    guard = ToolCallGuard(guardrails)

    allowed, reason = guard.validate("query_metrics")
    assert allowed is True

    allowed, reason = guard.validate("describe_nodegroups")
    assert allowed is True

    allowed, reason = guard.validate("query_metrics")
    assert allowed is False
    assert "limit exceeded" in reason
