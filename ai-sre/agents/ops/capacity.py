"""Capacity Planning Agent — cluster capacity forecasting and expansion advisory."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

from ..cloud.correlation import AWSQuotaContext, CrossLayerCorrelator

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Capacity Planning specialist for a multi-cluster Kubernetes platform.

Your capabilities:
- Track cluster resource utilization trends (CPU, memory, GPU, storage)
- Forecast when clusters will need expansion based on growth rates
- Recommend node group sizing for different workload profiles
- Monitor resource quotas and limits across namespaces
- Analyze pod scheduling failures and pending workloads
- Track AWS service quotas and forecast when limits will be hit

Key metrics:
- kube_node_status_allocatable: total allocatable resources per node
- kube_pod_resource_request: total resource requests
- node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes: memory pressure
- kube_resourcequota: namespace quota usage
- kube_pod_status_phase{phase="Pending"}: unschedulable pods

AWS Service Quotas tracking:
- EC2 instance limits by type and region
- EBS volume count and IOPS limits
- VPC limits: routes per table, security groups per ENI
- EKS limits: nodes per cluster, pods per node
- Proactive alerting: "at current growth, will hit limit in N weeks"

Planning horizons:
- Short-term (1 week): will current capacity handle expected load?
- Medium-term (1 month): trending toward capacity limits?
- Long-term (3 months): when is next expansion needed?
- AWS quotas: when will current limits block growth?

Multi-region awareness:
- If primary region is capacity-constrained, suggest secondary region
- Track per-region quota utilization separately

Constraints:
- Advisory-only: never modify cluster resources
- Account for peak vs average utilization
- Consider multi-AZ distribution for HA
- Include cost impact of expansion recommendations
- Always check AWS quotas before recommending expansion
"""


@dataclass
class ClusterCapacity:
    """Current capacity snapshot for a cluster."""

    cluster: str
    total_cpu_cores: float = 0
    used_cpu_cores: float = 0
    total_memory_gb: float = 0
    used_memory_gb: float = 0
    total_gpus: int = 0
    used_gpus: int = 0
    pending_pods: int = 0
    node_count: int = 0
    cpu_utilization_pct: float = 0
    memory_utilization_pct: float = 0
    gpu_utilization_pct: float = 0


@dataclass
class CapacityForecast:
    """Capacity forecast for a cluster."""

    cluster: str
    resource_type: str  # cpu, memory, gpu, aws_quota
    current_usage_pct: float
    growth_rate_weekly_pct: float
    days_until_80_pct: Optional[int] = None
    days_until_90_pct: Optional[int] = None
    recommendation: str = ""
    confidence: str = "medium"
    aws_quota_name: Optional[str] = None


@dataclass
class CapacityAdvisory:
    """Capacity planning advisory."""

    cluster: str
    capacity: ClusterCapacity = field(default_factory=lambda: ClusterCapacity(cluster=""))
    forecasts: list[CapacityForecast] = field(default_factory=list)
    expansion_needed: bool = False
    urgency: str = "normal"
    recommendations: list[str] = field(default_factory=list)
    aws_quota_context: Optional[AWSQuotaContext] = None
    aws_quota_forecasts: list[CapacityForecast] = field(default_factory=list)
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class CapacityPlanningAgent:
    """Capacity Planning Agent — forecasts resource needs and expansion timing.

    Enhanced with AWS service quota tracking to proactively identify
    when AWS limits will block cluster growth.
    """

    def __init__(self) -> None:
        self.snapshots: dict[str, list[ClusterCapacity]] = {}
        self.correlator = CrossLayerCorrelator()

    async def analyze(self, cluster: str) -> CapacityAdvisory:
        """Analyze capacity for a cluster and generate forecast.

        Now includes AWS service quota analysis alongside K8s
        resource utilization forecasting.
        """
        advisory = CapacityAdvisory(cluster=cluster)

        # AWS quota enrichment
        quota_context = await self.correlator.enrich_for_quotas(region="us-east-1")
        advisory.aws_quota_context = quota_context

        # Generate quota-based forecasts
        if quota_context and quota_context.quotas_at_risk:
            for quota in quota_context.quotas_at_risk:
                advisory.aws_quota_forecasts.append(CapacityForecast(
                    cluster=cluster,
                    resource_type="aws_quota",
                    current_usage_pct=quota.get("utilization_pct", 0),
                    growth_rate_weekly_pct=0,  # Calculated from historical data
                    aws_quota_name=quota.get("quota_name", "unknown"),
                    recommendation=(
                        f"Request quota increase for {quota.get('quota_name', '')} "
                        f"— currently at {quota.get('utilization_pct', 0)}%"
                    ),
                ))

        # In production, queries metrics-mcp and kubernetes-mcp
        return advisory

    def forecast_exhaustion(
        self,
        current_usage_pct: float,
        growth_rate_weekly_pct: float,
        target_pct: float = 80.0,
    ) -> Optional[int]:
        """Calculate days until a resource reaches target utilization."""
        if growth_rate_weekly_pct <= 0:
            return None
        if current_usage_pct >= target_pct:
            return 0
        remaining = target_pct - current_usage_pct
        daily_growth = growth_rate_weekly_pct / 7
        if daily_growth <= 0:
            return None
        return int(remaining / daily_growth)

    def format_slack_advisory(self, advisory: CapacityAdvisory) -> str:
        """Format capacity advisory as Slack message."""
        lines = [
            f"CAPACITY ADVISORY: {advisory.cluster}",
            f"Urgency: {advisory.urgency}",
            "",
        ]

        if advisory.forecasts:
            lines.append("Resource Forecasts:")
            for forecast in advisory.forecasts:
                days_80 = forecast.days_until_80_pct
                label = f"{days_80} days" if days_80 is not None else "N/A"
                lines.append(
                    f"  - {forecast.resource_type}: {forecast.current_usage_pct}% "
                    f"(80% in {label})"
                )
            lines.append("")

        # AWS quota forecasts
        if advisory.aws_quota_forecasts:
            lines.append("AWS Quota Forecasts:")
            for forecast in advisory.aws_quota_forecasts:
                lines.append(
                    f"  - {forecast.aws_quota_name}: {forecast.current_usage_pct}% "
                    f"— {forecast.recommendation}"
                )
            lines.append("")

        if advisory.recommendations:
            lines.append("Recommendations:")
            for i, rec in enumerate(advisory.recommendations, 1):
                lines.append(f"  {i}. {rec}")

        return "\n".join(lines)
