"""Predictive Scaling Agent — demand forecasting and proactive scaling recommendations."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Predictive Scaling specialist for GPU inference workloads
on a multi-cluster Kubernetes platform using Karpenter for node provisioning.

Your capabilities:
- Forecast demand based on historical patterns (hourly, daily, weekly cycles)
- Monitor vLLM queue depth and inference latency as leading indicators
- Recommend proactive scaling actions before demand spikes
- Advise on Karpenter NodePool and EC2NodeClass adjustments
- Analyze GPU utilization efficiency across the fleet

Key metrics you monitor:
- vllm_num_requests_waiting: inference request queue depth
- vllm_avg_generation_throughput_toks_per_s: generation throughput
- vllm_gpu_cache_usage_perc: KV cache utilization
- DCGM_FI_DEV_GPU_UTIL: GPU compute utilization
- kube_pod_status_phase{phase="Pending"}: pods waiting for resources
- karpenter_provisioner_scheduling_duration_seconds: provisioning latency

Scaling strategy:
1. If queue_depth > threshold for 5 min: scale up immediately
2. If historical pattern shows peak in next 30 min: pre-scale
3. If GPU utilization < 20% for 30 min: recommend scale down
4. Always maintain headroom for burst traffic (10-20% spare capacity)

Constraints:
- Advisory-only: recommend scaling actions, never execute
- Consider cost implications of scaling decisions
- Prefer spot instances for fault-tolerant workloads
- Respect Karpenter consolidation policies
"""


@dataclass
class DemandForecast:
    """Demand forecast for a workload."""

    service: str
    cluster: str
    current_replicas: int
    current_queue_depth: float
    current_gpu_utilization: float
    predicted_demand_30m: float
    predicted_demand_1h: float
    predicted_demand_4h: float
    confidence: str = "medium"
    pattern: str = ""  # daily_peak, weekly_cycle, event_driven, steady


@dataclass
class ScalingRecommendation:
    """A scaling recommendation from the agent."""

    action: str  # scale_up, scale_down, pre_scale, no_change
    service: str
    cluster: str
    current_replicas: int
    target_replicas: int
    reason: str
    urgency: str = "normal"  # immediate, proactive, normal
    estimated_cost_change: Optional[str] = None
    karpenter_config: Optional[dict[str, Any]] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


@dataclass
class ScalingAdvisory:
    """Advisory output from the scaling agent."""

    cluster: str
    forecasts: list[DemandForecast] = field(default_factory=list)
    recommendations: list[ScalingRecommendation] = field(default_factory=list)
    fleet_utilization: float = 0.0
    spare_capacity_percent: float = 0.0
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


# Scaling thresholds
QUEUE_DEPTH_SCALE_UP = 10.0
QUEUE_DEPTH_CRITICAL = 50.0
GPU_UTIL_LOW = 20.0
GPU_UTIL_HIGH = 85.0
SPARE_CAPACITY_TARGET = 15.0  # percent


class PredictiveScalingAgent:
    """Predictive Scaling Agent — forecasts demand and recommends scaling.

    Uses metrics-mcp for VictoriaMetrics queries and aws-mcp for
    node group and Karpenter information.
    """

    def __init__(self) -> None:
        self.forecasts: dict[str, DemandForecast] = {}
        self.recommendations: list[ScalingRecommendation] = []

    async def analyze(
        self,
        cluster: str,
        service: Optional[str] = None,
    ) -> ScalingAdvisory:
        """Analyze current state and generate scaling advisory.

        In production, queries:
        1. Current vLLM metrics (queue depth, throughput, cache usage)
        2. GPU utilization across fleet
        3. Historical demand patterns (last 7 days)
        4. Karpenter NodePool status
        5. Pending pod count
        """
        advisory = ScalingAdvisory(cluster=cluster)

        # In production, MCP tools provide data for forecasting
        # The agent then reasons about patterns and generates recommendations

        return advisory

    def evaluate_scaling_need(
        self,
        queue_depth: float,
        gpu_utilization: float,
        current_replicas: int,
        service: str,
        cluster: str,
    ) -> ScalingRecommendation:
        """Evaluate if scaling is needed based on current metrics."""
        if queue_depth > QUEUE_DEPTH_CRITICAL:
            target = min(current_replicas * 2, current_replicas + 8)
            return ScalingRecommendation(
                action="scale_up",
                service=service,
                cluster=cluster,
                current_replicas=current_replicas,
                target_replicas=target,
                reason=(
                    f"Queue depth {queue_depth} exceeds critical threshold "
                    f"({QUEUE_DEPTH_CRITICAL}). Immediate scale-up needed."
                ),
                urgency="immediate",
            )

        if queue_depth > QUEUE_DEPTH_SCALE_UP:
            target = current_replicas + max(1, int(queue_depth / QUEUE_DEPTH_SCALE_UP))
            return ScalingRecommendation(
                action="scale_up",
                service=service,
                cluster=cluster,
                current_replicas=current_replicas,
                target_replicas=target,
                reason=(
                    f"Queue depth {queue_depth} above scale-up threshold "
                    f"({QUEUE_DEPTH_SCALE_UP}). Proactive scaling recommended."
                ),
                urgency="proactive",
            )

        if gpu_utilization < GPU_UTIL_LOW and current_replicas > 1:
            target = max(1, current_replicas - 1)
            return ScalingRecommendation(
                action="scale_down",
                service=service,
                cluster=cluster,
                current_replicas=current_replicas,
                target_replicas=target,
                reason=(
                    f"GPU utilization {gpu_utilization}% below threshold "
                    f"({GPU_UTIL_LOW}%). Cost savings available."
                ),
                urgency="normal",
                estimated_cost_change="Savings: ~$X/hour per reduced replica",
            )

        return ScalingRecommendation(
            action="no_change",
            service=service,
            cluster=cluster,
            current_replicas=current_replicas,
            target_replicas=current_replicas,
            reason=(
                f"Queue depth {queue_depth} and GPU utilization "
                f"{gpu_utilization}% within normal range."
            ),
        )

    def format_slack_advisory(self, advisory: ScalingAdvisory) -> str:
        """Format scaling advisory as Slack message."""
        lines = [
            f"SCALING ADVISORY: {advisory.cluster}",
            f"Fleet Utilization: {advisory.fleet_utilization}%",
            f"Spare Capacity: {advisory.spare_capacity_percent}%",
            "",
        ]

        for rec in advisory.recommendations:
            if rec.action == "no_change":
                continue
            emoji = "UP" if "up" in rec.action else "DOWN"
            lines.extend([
                f"  {rec.service}: {rec.action.upper()} "
                f"({rec.current_replicas} -> {rec.target_replicas})",
                f"  Reason: {rec.reason}",
                f"  Urgency: {rec.urgency}",
                "",
            ])

        return "\n".join(lines)
