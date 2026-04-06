"""Cost Optimization Agent — identifies savings opportunities across the GPU fleet."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Cost Optimization specialist for a multi-cluster Kubernetes
platform with significant GPU infrastructure spending.

Your capabilities:
- Identify idle and underutilized GPU resources
- Recommend right-sizing for node groups and instance types
- Advise on spot instance usage for fault-tolerant workloads
- Track cost trends and detect anomalies
- Calculate cost per inference request / training job
- Compare reserved vs on-demand vs spot pricing

Key cost factors:
- GPU instances: p5.48xlarge (H100), p4d.24xlarge (A100) — highest cost items
- Cross-AZ data transfer: significant for multi-GPU training
- EBS volumes: gp3 vs io2 for model storage
- NAT Gateway: egress costs for external API calls

Cost optimization strategies:
1. Idle GPU detection: nodes with <10% GPU utilization for 30+ min
2. Right-sizing: downgrade instance type if GPU memory/compute underused
3. Spot instances: use for inference replicas with graceful shutdown
4. Scheduling: turn off dev/staging GPU nodes outside business hours
5. Storage: optimize model caching to reduce EBS costs
6. Network: minimize cross-AZ traffic for distributed training

Constraints:
- Advisory-only: recommend changes, never execute
- Always quantify savings in $/hour or $/month
- Consider reliability impact of cost optimizations
- Never recommend spot for stateful training jobs
"""


@dataclass
class CostAnomaly:
    """A detected cost anomaly."""

    resource: str
    cluster: str
    expected_cost: float
    actual_cost: float
    deviation_percent: float
    description: str
    first_detected: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


@dataclass
class SavingsOpportunity:
    """An identified cost savings opportunity."""

    category: str  # idle_gpu, right_sizing, spot, scheduling, storage, network
    resource: str
    cluster: str
    current_cost_hourly: float
    projected_cost_hourly: float
    savings_hourly: float
    savings_monthly: float
    description: str
    risk_level: str = "low"  # low, medium, high
    implementation_effort: str = "low"  # low, medium, high
    recommended_action: str = ""


@dataclass
class CostReport:
    """Cost optimization report for a cluster or fleet."""

    cluster: Optional[str] = None
    total_hourly_cost: float = 0.0
    gpu_hourly_cost: float = 0.0
    gpu_utilization_avg: float = 0.0
    idle_gpu_count: int = 0
    anomalies: list[CostAnomaly] = field(default_factory=list)
    opportunities: list[SavingsOpportunity] = field(default_factory=list)
    total_potential_savings_monthly: float = 0.0
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


# Instance pricing (us-east-1, approximate on-demand $/hr)
INSTANCE_PRICING: dict[str, float] = {
    "p5.48xlarge": 98.32,    # 8x H100 80GB
    "p4d.24xlarge": 32.77,   # 8x A100 40GB
    "p4de.24xlarge": 40.97,  # 8x A100 80GB
    "g5.48xlarge": 16.29,    # 8x A10G
    "g5.xlarge": 1.006,      # 1x A10G
    "g6.xlarge": 0.805,      # 1x L4
    "m7i.4xlarge": 0.806,    # CPU-only (platform)
}

# Spot discount estimates
SPOT_DISCOUNT: dict[str, float] = {
    "p5.48xlarge": 0.40,     # ~60% savings
    "p4d.24xlarge": 0.35,    # ~65% savings
    "g5.48xlarge": 0.45,     # ~55% savings
    "g5.xlarge": 0.50,       # ~50% savings
}

# Idle GPU threshold
IDLE_GPU_UTIL_THRESHOLD = 10.0  # percent
IDLE_GPU_DURATION_MIN = 30  # minutes


class CostOptimizationAgent:
    """Cost Optimization Agent — finds savings across the GPU fleet.

    Uses aws-mcp for pricing and instance data, metrics-mcp for
    utilization metrics, kubernetes-mcp for workload analysis.
    """

    def __init__(self) -> None:
        self.reports: dict[str, CostReport] = {}

    async def analyze(
        self,
        cluster: Optional[str] = None,
    ) -> CostReport:
        """Run full cost analysis for a cluster or the entire fleet.

        In production, queries:
        1. AWS Cost Explorer for actual spend
        2. VictoriaMetrics for GPU/CPU utilization
        3. K8s API for node types and counts
        4. Karpenter for provisioning patterns
        """
        report = CostReport(cluster=cluster)

        # In production, MCP tools provide data
        # Agent reasons about cost optimization opportunities

        return report

    def detect_idle_gpus(
        self,
        nodes: list[dict[str, Any]],
    ) -> list[SavingsOpportunity]:
        """Identify GPU nodes with utilization below threshold."""
        opportunities = []

        for node in nodes:
            gpu_util = node.get("gpu_utilization", 0)
            instance_type = node.get("instance_type", "unknown")
            node_name = node.get("name", "unknown")
            cluster = node.get("cluster", "unknown")

            if gpu_util < IDLE_GPU_UTIL_THRESHOLD:
                hourly_cost = INSTANCE_PRICING.get(instance_type, 0)
                opportunities.append(SavingsOpportunity(
                    category="idle_gpu",
                    resource=node_name,
                    cluster=cluster,
                    current_cost_hourly=hourly_cost,
                    projected_cost_hourly=0,
                    savings_hourly=hourly_cost,
                    savings_monthly=hourly_cost * 730,
                    description=(
                        f"Node {node_name} ({instance_type}) has {gpu_util}% "
                        f"GPU utilization — idle for extended period"
                    ),
                    risk_level="low",
                    recommended_action=(
                        f"Consider terminating or scaling down node {node_name}. "
                        f"Verify no pending workloads before removal."
                    ),
                ))

        return opportunities

    def evaluate_spot_opportunity(
        self,
        instance_type: str,
        current_count: int,
        workload_type: str,
    ) -> Optional[SavingsOpportunity]:
        """Evaluate if workloads can benefit from spot instances."""
        if workload_type in ("training", "stateful"):
            return None  # Never recommend spot for stateful workloads

        discount = SPOT_DISCOUNT.get(instance_type)
        if not discount:
            return None

        on_demand_cost = INSTANCE_PRICING.get(instance_type, 0)
        spot_cost = on_demand_cost * (1 - discount)
        savings = (on_demand_cost - spot_cost) * current_count

        return SavingsOpportunity(
            category="spot",
            resource=f"{current_count}x {instance_type}",
            cluster="",
            current_cost_hourly=on_demand_cost * current_count,
            projected_cost_hourly=spot_cost * current_count,
            savings_hourly=savings,
            savings_monthly=savings * 730,
            description=(
                f"Switch {current_count}x {instance_type} from on-demand to spot. "
                f"Estimated {discount * 100:.0f}% discount."
            ),
            risk_level="medium",
            implementation_effort="medium",
            recommended_action=(
                f"Configure Karpenter NodePool to prefer spot for {workload_type} "
                f"workloads. Ensure graceful shutdown handlers are in place."
            ),
        )

    def format_slack_report(self, report: CostReport) -> str:
        """Format cost report as Slack message."""
        scope = report.cluster or "All Clusters"
        lines = [
            f"COST OPTIMIZATION REPORT: {scope}",
            f"Total Hourly: ${report.total_hourly_cost:.2f}/hr "
            f"(GPU: ${report.gpu_hourly_cost:.2f}/hr)",
            f"Fleet GPU Utilization: {report.gpu_utilization_avg:.1f}%",
            f"Idle GPU Nodes: {report.idle_gpu_count}",
            "",
        ]

        if report.anomalies:
            lines.append("Cost Anomalies:")
            for anomaly in report.anomalies:
                lines.append(
                    f"  - {anomaly.resource}: "
                    f"+{anomaly.deviation_percent:.0f}% "
                    f"({anomaly.description})"
                )
            lines.append("")

        if report.opportunities:
            lines.append("Savings Opportunities:")
            for opp in report.opportunities:
                lines.append(
                    f"  - [{opp.category}] {opp.description} "
                    f"(~${opp.savings_monthly:.0f}/mo)"
                )
            lines.append("")
            lines.append(
                f"Total Potential Savings: "
                f"${report.total_potential_savings_monthly:.0f}/month"
            )

        return "\n".join(lines)
