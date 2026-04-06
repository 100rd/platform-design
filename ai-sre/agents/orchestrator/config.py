"""Agent configuration and definitions for the AI SRE system."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class AgentModel(str, Enum):
    """Claude model tiers for agent roles."""

    ORCHESTRATOR = "claude-opus-4-20250514"
    WORKER = "claude-sonnet-4-20250514"


class AgentRole(str, Enum):
    """Specialized SRE agent roles."""

    ORCHESTRATOR = "orchestrator"
    INCIDENT_RESPONSE = "incident-response"
    GPU_HEALTH = "gpu-health"
    PREDICTIVE_SCALING = "predictive-scaling"
    COST_OPTIMIZATION = "cost-optimization"
    CAPACITY_PLANNING = "capacity-planning"
    CHAOS_ENGINEERING = "chaos-engineering"
    ONCALL_COPILOT = "oncall-copilot"
    RUNBOOK_AUTOMATION = "runbook-automation"


@dataclass
class ToolPermission:
    """MCP tool access permission for an agent."""

    server: str
    tools: list[str] = field(default_factory=list)
    read_only: bool = True


@dataclass
class AgentDefinition:
    """Definition for a specialized SRE agent."""

    role: AgentRole
    model: AgentModel
    system_prompt: str
    tool_permissions: list[ToolPermission] = field(default_factory=list)
    max_tokens: int = 4096
    temperature: float = 0.0


# Default tool permissions per agent role
AGENT_TOOL_PERMISSIONS: dict[AgentRole, list[ToolPermission]] = {
    AgentRole.ORCHESTRATOR: [
        ToolPermission(server="kubernetes-mcp", tools=["*"], read_only=True),
        ToolPermission(server="aws-mcp", tools=["*"], read_only=True),
        ToolPermission(server="metrics-mcp", tools=["*"], read_only=True),
        ToolPermission(server="slack-mcp", tools=["*"], read_only=False),
        ToolPermission(server="runbook-mcp", tools=["*"], read_only=True),
        ToolPermission(server="git-mcp", tools=["*"], read_only=True),
    ],
    AgentRole.INCIDENT_RESPONSE: [
        ToolPermission(server="kubernetes-mcp", tools=["*"], read_only=True),
        ToolPermission(server="metrics-mcp", tools=["*"], read_only=True),
        ToolPermission(server="git-mcp", tools=["*"], read_only=True),
        ToolPermission(server="runbook-mcp", tools=["*"], read_only=True),
    ],
    AgentRole.GPU_HEALTH: [
        ToolPermission(
            server="kubernetes-mcp",
            tools=["list_pods", "get_pod", "get_pod_logs", "get_node", "list_nodes"],
            read_only=True,
        ),
        ToolPermission(
            server="metrics-mcp",
            tools=["query_metrics", "get_gpu_health"],
            read_only=True,
        ),
    ],
    AgentRole.PREDICTIVE_SCALING: [
        ToolPermission(
            server="metrics-mcp",
            tools=["query_metrics", "get_cluster_capacity"],
            read_only=True,
        ),
        ToolPermission(
            server="aws-mcp",
            tools=["describe_nodegroups", "describe_autoscaling"],
            read_only=True,
        ),
    ],
    AgentRole.COST_OPTIMIZATION: [
        ToolPermission(server="aws-mcp", tools=["*"], read_only=True),
        ToolPermission(
            server="metrics-mcp",
            tools=["query_metrics", "get_cluster_capacity"],
            read_only=True,
        ),
    ],
    AgentRole.CAPACITY_PLANNING: [
        ToolPermission(
            server="kubernetes-mcp",
            tools=["list_nodes", "get_node", "list_pods"],
            read_only=True,
        ),
        ToolPermission(
            server="metrics-mcp",
            tools=["query_metrics", "get_cluster_capacity"],
            read_only=True,
        ),
    ],
    AgentRole.CHAOS_ENGINEERING: [
        ToolPermission(server="kubernetes-mcp", tools=["*"], read_only=True),
        ToolPermission(server="metrics-mcp", tools=["*"], read_only=True),
    ],
    AgentRole.ONCALL_COPILOT: [
        ToolPermission(server="kubernetes-mcp", tools=["*"], read_only=True),
        ToolPermission(server="metrics-mcp", tools=["*"], read_only=True),
        ToolPermission(server="runbook-mcp", tools=["*"], read_only=True),
        ToolPermission(server="slack-mcp", tools=["*"], read_only=False),
    ],
    AgentRole.RUNBOOK_AUTOMATION: [
        ToolPermission(server="runbook-mcp", tools=["*"], read_only=False),
        ToolPermission(server="kubernetes-mcp", tools=["*"], read_only=True),
        ToolPermission(server="metrics-mcp", tools=["*"], read_only=True),
    ],
}

# System prompts for each agent role
AGENT_SYSTEM_PROMPTS: dict[AgentRole, str] = {
    AgentRole.ORCHESTRATOR: """You are the SRE Orchestrator Agent for a multi-cluster Kubernetes platform.

Your role:
- Receive alerts and questions from Slack and the alert ingestion pipeline
- Route investigations to the appropriate specialized agent
- Aggregate findings from multiple agents into a single advisory
- Enforce advisory-only mode: you NEVER take autonomous actions
- All write operations require explicit human approval via Slack

Clusters you monitor: platform (hub), blockchain, gpu-analysis, gpu-inference.

Always provide:
1. A clear summary of the situation
2. Root cause hypothesis with confidence level
3. Recommended actions (not auto-executed)
4. Related past incidents if available
""",
    AgentRole.INCIDENT_RESPONSE: """You are the Incident Response Agent for a multi-cluster Kubernetes platform.

Your role:
- Perform root cause analysis with multi-signal correlation
- Correlate metrics, logs, events, and recent deployments
- Check for similar past incidents in the knowledge base
- Produce a structured incident report

Always investigate:
1. Recent deployments (last 2 hours)
2. Resource pressure (CPU, memory, disk)
3. Network issues (Cilium, DNS)
4. Dependent service health
""",
    AgentRole.GPU_HEALTH: """You are the GPU Health Agent for GPU-accelerated Kubernetes clusters.

Your role:
- Monitor DCGM metrics for GPU health indicators
- Detect XID errors, ECC errors, thermal throttling
- Predict GPU failures before they impact workloads
- Advise on node cordoning and workload migration

Key metrics: dcgm_gpu_temp, dcgm_ecc_errors, dcgm_xid_errors, dcgm_gpu_utilization.
""",
    AgentRole.PREDICTIVE_SCALING: """You are the Predictive Scaling Agent for GPU inference workloads.

Your role:
- Forecast demand based on historical patterns
- Recommend scaling actions before demand spikes
- Monitor vLLM queue depth and inference latency
- Advise on Karpenter provisioner adjustments

Key signals: vllm_request_queue_size, inference_latency_p99, gpu_utilization trends.
""",
    AgentRole.COST_OPTIMIZATION: """You are the Cost Optimization Agent for multi-cluster infrastructure.

Your role:
- Identify idle GPU resources across clusters
- Recommend right-sizing for node groups
- Advise on spot instance usage for fault-tolerant workloads
- Track cost trends and anomalies

Always consider: GPU utilization efficiency, reserved vs on-demand, cross-AZ traffic costs.
""",
    AgentRole.CAPACITY_PLANNING: """You are the Capacity Planning Agent.

Your role:
- Track cluster capacity utilization trends
- Forecast when clusters will need expansion
- Recommend node group sizing
- Monitor resource quotas and limits
""",
    AgentRole.CHAOS_ENGINEERING: """You are the Chaos Engineering Agent.

Your role:
- Suggest chaos experiments based on system topology
- Analyze blast radius of potential failures
- Review resilience gaps in the architecture
- Recommend improvements based on chaos test results

You NEVER execute chaos experiments autonomously. All experiments require human approval.
""",
    AgentRole.ONCALL_COPILOT: """You are the On-Call Copilot Agent.

Your role:
- Assist on-call engineers with alert investigation
- Provide context from knowledge base and past incidents
- Suggest relevant runbooks for current issues
- Help draft incident communications
""",
    AgentRole.RUNBOOK_AUTOMATION: """You are the Runbook Automation Agent.

Your role:
- Execute pre-approved runbook steps automatically
- Request human approval for privileged operations
- Log all runbook executions for audit
- Suggest runbook improvements based on execution patterns
""",
}
