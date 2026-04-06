"""Read-only enforcement for AI SRE agents (Defense in Depth).

Implements Layer 4 (Agent SDK Guardrails) of the defense-in-depth strategy:
- Layer 1: MCP Server Config (KUBERNETES_MCP_READ_ONLY=true, IAM read-only)
- Layer 2: RBAC (ClusterRole with only get/list/watch)
- Layer 3: Network Policy (egress only to approved endpoints)
- Layer 4: Agent SDK Guardrails (this module)

This module enforces tool allowlists, call limits, and token budgets
at the application layer as the final line of defense.
"""

import logging
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger(__name__)


# Verbs that indicate write operations
WRITE_VERBS = frozenset({
    "create", "update", "patch", "delete", "apply",
    "cordon", "uncordon", "drain", "taint",
    "scale", "rollout", "restart",
    "insert", "alter", "drop", "truncate",
})


@dataclass
class AgentGuardrails:
    """Per-agent guardrail configuration enforced at SDK level."""

    agent_role: str
    allowed_tools: list[str] = field(default_factory=list)
    max_tool_calls: int = 50
    max_tokens_per_response: int = 8000
    timeout_seconds: int = 300
    read_only: bool = True

    # Runtime counters
    _tool_call_count: int = field(default=0, init=False, repr=False)
    _total_tokens: int = field(default=0, init=False, repr=False)


# Default guardrails per agent role (principle of least privilege)
DEFAULT_GUARDRAILS: dict[str, AgentGuardrails] = {
    "orchestrator": AgentGuardrails(
        agent_role="orchestrator",
        allowed_tools=["*"],
        max_tool_calls=50,
        max_tokens_per_response=8000,
        timeout_seconds=300,
    ),
    "incident-response": AgentGuardrails(
        agent_role="incident-response",
        allowed_tools=[
            "list_pods", "get_pod", "get_pod_logs", "get_events",
            "describe_resource", "list_nodes", "get_node",
            "query_metrics", "query_logs", "get_error_rate",
            "get_latency_percentiles", "search_incidents",
            "get_runbook", "suggest_runbook",
            "list_commits", "get_diff",
        ],
        max_tool_calls=50,
        timeout_seconds=300,
    ),
    "gpu-health": AgentGuardrails(
        agent_role="gpu-health",
        allowed_tools=[
            "list_pods", "get_pod", "get_pod_logs",
            "list_nodes", "get_node",
            "query_metrics", "get_gpu_health",
        ],
        max_tool_calls=30,
        timeout_seconds=180,
    ),
    "predictive-scaling": AgentGuardrails(
        agent_role="predictive-scaling",
        allowed_tools=[
            "query_metrics", "get_cluster_capacity",
            "describe_nodegroups", "describe_autoscaling",
        ],
        max_tool_calls=30,
        timeout_seconds=180,
    ),
    "cost-optimization": AgentGuardrails(
        agent_role="cost-optimization",
        allowed_tools=[
            "query_metrics", "get_cluster_capacity",
            "describe_instances", "get_pricing",
            "describe_nodegroups", "describe_reserved_instances",
        ],
        max_tool_calls=30,
        timeout_seconds=180,
    ),
    "capacity-planning": AgentGuardrails(
        agent_role="capacity-planning",
        allowed_tools=[
            "list_nodes", "get_node", "list_pods",
            "query_metrics", "get_cluster_capacity",
        ],
        max_tool_calls=30,
        timeout_seconds=180,
    ),
    "chaos-engineering": AgentGuardrails(
        agent_role="chaos-engineering",
        allowed_tools=[
            "list_pods", "get_pod", "list_nodes", "get_node",
            "query_metrics", "get_cluster_capacity",
            "get_cluster_topology",
        ],
        max_tool_calls=30,
        timeout_seconds=180,
    ),
    "oncall-copilot": AgentGuardrails(
        agent_role="oncall-copilot",
        allowed_tools=["*"],
        max_tool_calls=50,
        timeout_seconds=300,
    ),
    "runbook-automation": AgentGuardrails(
        agent_role="runbook-automation",
        allowed_tools=[
            "list_runbooks", "get_runbook", "suggest_runbook",
            "execute_runbook_step",
            "list_pods", "get_pod", "get_pod_logs",
            "query_metrics",
        ],
        max_tool_calls=50,
        timeout_seconds=300,
        read_only=False,
    ),
}


class ToolCallGuard:
    """Validates tool calls against agent guardrails before execution.

    Checks:
    1. Tool is in the agent's allowlist
    2. Tool call count hasn't exceeded limit
    3. Tool doesn't perform write operations (unless explicitly allowed)
    """

    def __init__(self, guardrails: AgentGuardrails) -> None:
        self.guardrails = guardrails
        self._call_count = 0

    def validate(
        self, tool_name: str, tool_input: Optional[dict[str, Any]] = None
    ) -> tuple[bool, str]:
        """Validate a tool call against guardrails.

        Returns (allowed, reason) tuple.
        """
        # Check call count limit
        self._call_count += 1
        if self._call_count > self.guardrails.max_tool_calls:
            reason = (
                f"Tool call limit exceeded: {self._call_count} > "
                f"{self.guardrails.max_tool_calls}"
            )
            logger.warning(
                "tool_call_blocked",
                reason="call_limit_exceeded",
                agent=self.guardrails.agent_role,
                tool=tool_name,
            )
            return False, reason

        # Check tool allowlist
        if (
            "*" not in self.guardrails.allowed_tools
            and tool_name not in self.guardrails.allowed_tools
        ):
            reason = (
                f"Tool '{tool_name}' not in allowlist for "
                f"agent '{self.guardrails.agent_role}'"
            )
            logger.warning(
                "tool_call_blocked",
                reason="not_in_allowlist",
                agent=self.guardrails.agent_role,
                tool=tool_name,
            )
            return False, reason

        # Check for write operations in read-only mode
        if self.guardrails.read_only and _is_write_operation(tool_name, tool_input):
            reason = (
                f"Write operation '{tool_name}' blocked for read-only "
                f"agent '{self.guardrails.agent_role}'"
            )
            logger.warning(
                "tool_call_blocked",
                reason="write_in_readonly",
                agent=self.guardrails.agent_role,
                tool=tool_name,
            )
            return False, reason

        return True, "allowed"

    @property
    def calls_remaining(self) -> int:
        """Number of tool calls remaining before limit."""
        return max(0, self.guardrails.max_tool_calls - self._call_count)


def _is_write_operation(
    tool_name: str, tool_input: Optional[dict[str, Any]] = None
) -> bool:
    """Detect if a tool call represents a write operation."""
    name_lower = tool_name.lower()

    # Check tool name for write verb prefixes
    for verb in WRITE_VERBS:
        if verb in name_lower:
            return True

    # Check tool input for write-like commands
    if tool_input:
        for value in tool_input.values():
            if isinstance(value, str):
                value_lower = value.lower()
                for verb in WRITE_VERBS:
                    if verb in value_lower:
                        return True

    return False


def get_guardrails(agent_role: str) -> AgentGuardrails:
    """Get guardrails for a specific agent role."""
    return DEFAULT_GUARDRAILS.get(
        agent_role,
        AgentGuardrails(agent_role=agent_role, max_tool_calls=20),
    )
