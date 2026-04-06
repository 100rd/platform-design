"""Capacity Planning Agent — cluster capacity forecasting and expansion advisory."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Capacity Planning specialist for a multi-cluster Kubernetes platform.

Your capabilities:
- Track cluster resource utilization trends (CPU, memory, GPU, storage)
- Forecast when clusters will need expansion based on growth rates
- Recommend node group sizing for different workload profiles
- Monitor resource quotas and limits across namespaces
- Analyze pod scheduling failures and pending workloads

Key metrics:
- kube_node_status_allocatable: total allocatable resources per node
- kube_pod_resource_request: total resource requests
- node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes: memory pressure
- kube_resourcequota: namespace quota usage
- kube_pod_status_phase{phase="Pending"}: unschedulable pods

Planning horizons:
- Short-term (1 week): will current capacity handle expected load?
- Medium-term (1 month): trending toward capacity limits?
- Long-term (3 months): when is next expansion needed?

Constraints:
- Advisory-only: never modify cluster resources
- Account for peak vs average utilization
- Consider multi-AZ distribution for HA
- Include cost impact of expansion recommendations
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
    resource_type: str  # cpu, memory, gpu
    current_usage_pct: float
    growth_rate_weekly_pct: float
    days_until_80_pct: Optional[int] = None
    days_until_90_pct: Optional[int] = None
    recommendation: str = ""
    confidence: str = "medium"


@dataclass
class CapacityAdvisory:
    """Capacity planning advisory."""

    cluster: str
    capacity: ClusterCapacity = field(default_factory=lambda: ClusterCapacity(cluster=""))
    forecasts: list[CapacityForecast] = field(default_factory=list)
    expansion_needed: bool = False
    urgency: str = "normal"
    recommendations: list[str] = field(default_factory=list)
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class CapacityPlanningAgent:
    """Capacity Planning Agent — forecasts resource needs and expansion timing."""

    def __init__(self) -> None:
        self.snapshots: dict[str, list[ClusterCapacity]] = {}

    async def analyze(self, cluster: str) -> CapacityAdvisory:
        """Analyze capacity for a cluster and generate forecast."""
        advisory = CapacityAdvisory(cluster=cluster)
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
