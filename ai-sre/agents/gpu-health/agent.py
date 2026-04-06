"""GPU Health Agent — predictive failure detection using DCGM metrics."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a GPU Health specialist for a multi-cluster Kubernetes platform
with NVIDIA GPU nodes (H100, A100) running inference and training workloads.

Your capabilities:
- Monitor DCGM metrics for GPU health indicators
- Detect XID errors, ECC errors, and thermal throttling
- Predict GPU failures before they impact workloads
- Analyze GPU utilization patterns and memory pressure
- Advise on node cordoning, workload migration, and driver issues

Key DCGM metrics you monitor:
- DCGM_FI_DEV_GPU_UTIL: GPU compute utilization (%)
- DCGM_FI_DEV_GPU_TEMP: GPU temperature (Celsius)
- DCGM_FI_DEV_MEM_COPY_UTIL: Memory utilization (%)
- DCGM_FI_DEV_ECC_SBE_VOL_TOTAL: Single-bit ECC errors (volatile)
- DCGM_FI_DEV_ECC_DBE_VOL_TOTAL: Double-bit ECC errors (volatile, CRITICAL)
- DCGM_FI_DEV_XID_ERRORS: XID error codes
- DCGM_FI_DEV_POWER_USAGE: Power consumption (W)
- DCGM_FI_DEV_PCIE_REPLAY_COUNTER: PCIe replay count
- DCGM_FI_PROF_NVLINK_TX_BYTES: NVLink transmit throughput

Thresholds:
- Temperature > 83C: thermal throttling imminent
- ECC DBE > 0: immediate action required (data corruption risk)
- XID 48 (DBE): double-bit ECC error — cordon and drain node
- XID 63: ECC page retirement — monitor, may need replacement
- XID 79: GPU fallen off bus — hardware failure, replace
- PCIe replays > 100/min: link degradation
- NVLink errors: training performance degradation

Constraints:
- Advisory-only: never execute commands
- Always recommend cordoning before draining
- Escalate hardware failures to on-call with evidence
"""


@dataclass
class GPUHealthMetrics:
    """Health metrics for a single GPU."""

    node: str
    gpu_index: int
    gpu_uuid: str = ""
    temperature: float = 0.0
    utilization: float = 0.0
    memory_utilization: float = 0.0
    power_usage: float = 0.0
    ecc_sbe_count: int = 0
    ecc_dbe_count: int = 0
    xid_errors: list[int] = field(default_factory=list)
    pcie_replay_count: int = 0
    nvlink_errors: int = 0


@dataclass
class GPUHealthAssessment:
    """Health assessment for a GPU or node."""

    node: str
    cluster: str
    status: str  # healthy, degraded, critical, failed
    risk_score: float = 0.0  # 0-100
    issues: list[str] = field(default_factory=list)
    predictions: list[str] = field(default_factory=list)
    recommended_actions: list[str] = field(default_factory=list)
    gpu_metrics: list[GPUHealthMetrics] = field(default_factory=list)
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


# XID error severity classification
XID_SEVERITY: dict[int, tuple[str, str]] = {
    13: ("warning", "Graphics Engine Exception — likely driver/app issue"),
    31: ("warning", "GPU memory page fault — check application memory access"),
    43: ("critical", "GPU stopped responding — possible hardware issue"),
    45: ("warning", "Preemptive cleanup — GPU context killed"),
    48: ("critical", "Double-bit ECC error — data corruption risk, cordon node"),
    63: ("warning", "ECC page retirement — monitor, may need GPU replacement"),
    64: ("warning", "ECC page retirement limit — replacement recommended"),
    74: ("critical", "NVLink error — degraded multi-GPU performance"),
    79: ("critical", "GPU fallen off bus — hardware failure, replace node"),
    92: ("critical", "High single-bit ECC error rate — GPU degrading"),
    94: ("warning", "Contained ECC error — monitor closely"),
    95: ("critical", "Uncontained ECC error — data integrity risk"),
}


class GPUHealthAgent:
    """GPU Health Agent — monitors and predicts GPU failures.

    Uses DCGM metrics via metrics-mcp and K8s node status via
    kubernetes-mcp to assess GPU health across clusters.
    """

    def __init__(self) -> None:
        self.assessments: dict[str, GPUHealthAssessment] = {}

    async def assess_node(
        self,
        node: str,
        cluster: str,
        metrics: Optional[GPUHealthMetrics] = None,
    ) -> GPUHealthAssessment:
        """Assess GPU health for a specific node.

        Analyzes DCGM metrics and generates a health assessment
        with risk score and recommended actions.
        """
        assessment = GPUHealthAssessment(
            node=node,
            cluster=cluster,
            status="healthy",
        )

        if metrics:
            assessment.gpu_metrics = [metrics]
            self._evaluate_metrics(assessment, metrics)

        self.assessments[f"{cluster}/{node}"] = assessment
        return assessment

    def _evaluate_metrics(
        self,
        assessment: GPUHealthAssessment,
        metrics: GPUHealthMetrics,
    ) -> None:
        """Evaluate GPU metrics against thresholds."""
        risk = 0.0

        # Temperature check
        if metrics.temperature > 83:
            assessment.issues.append(
                f"GPU temperature {metrics.temperature}C exceeds throttling threshold (83C)"
            )
            risk += 30
        elif metrics.temperature > 78:
            assessment.predictions.append(
                f"GPU temperature {metrics.temperature}C approaching throttling zone"
            )
            risk += 10

        # ECC errors
        if metrics.ecc_dbe_count > 0:
            assessment.issues.append(
                f"Double-bit ECC errors detected: {metrics.ecc_dbe_count} "
                "(data corruption risk)"
            )
            assessment.recommended_actions.extend([
                f"Cordon node {metrics.node} immediately",
                "Drain workloads to healthy nodes",
                "Escalate to hardware team for GPU replacement",
            ])
            risk += 50
            assessment.status = "critical"

        if metrics.ecc_sbe_count > 100:
            assessment.issues.append(
                f"High single-bit ECC error rate: {metrics.ecc_sbe_count}"
            )
            assessment.predictions.append(
                "GPU memory degrading — likely to develop double-bit errors"
            )
            risk += 25

        # XID errors
        for xid in metrics.xid_errors:
            if xid in XID_SEVERITY:
                severity, description = XID_SEVERITY[xid]
                assessment.issues.append(f"XID {xid}: {description}")
                if severity == "critical":
                    risk += 40
                    assessment.status = "critical"
                else:
                    risk += 15

        # PCIe replays
        if metrics.pcie_replay_count > 100:
            assessment.issues.append(
                f"PCIe replay count: {metrics.pcie_replay_count}/min (link degradation)"
            )
            risk += 20

        # NVLink errors
        if metrics.nvlink_errors > 0:
            assessment.issues.append(
                f"NVLink errors detected: {metrics.nvlink_errors}"
            )
            risk += 25

        assessment.risk_score = min(100, risk)

        # Update status based on risk
        if assessment.status != "critical":
            if risk >= 50:
                assessment.status = "degraded"
            elif risk >= 80:
                assessment.status = "critical"

    async def assess_cluster(self, cluster: str) -> list[GPUHealthAssessment]:
        """Assess GPU health across all nodes in a cluster.

        In production, queries metrics-mcp for all GPU nodes
        and generates per-node assessments.
        """
        # Would query: DCGM_FI_DEV_GPU_UTIL{cluster="<cluster>"}
        # and iterate over nodes
        return list(
            a for a in self.assessments.values() if a.cluster == cluster
        )

    def get_critical_nodes(self) -> list[GPUHealthAssessment]:
        """Return all nodes with critical GPU health status."""
        return [
            a for a in self.assessments.values()
            if a.status == "critical"
        ]

    def format_slack_alert(self, assessment: GPUHealthAssessment) -> str:
        """Format a GPU health assessment as a Slack message."""
        status_indicator = {
            "healthy": "GREEN",
            "degraded": "YELLOW",
            "critical": "RED",
            "failed": "BLACK",
        }

        lines = [
            f"GPU HEALTH: {assessment.node} ({assessment.cluster}) "
            f"— {assessment.status.upper()}",
            f"Risk Score: {assessment.risk_score}/100",
            "",
        ]

        if assessment.issues:
            lines.append("Issues:")
            for issue in assessment.issues:
                lines.append(f"  - {issue}")

        if assessment.predictions:
            lines.append("\nPredictions:")
            for pred in assessment.predictions:
                lines.append(f"  - {pred}")

        if assessment.recommended_actions:
            lines.append("\nRecommended Actions:")
            for i, action in enumerate(assessment.recommended_actions, 1):
                lines.append(f"  {i}. {action}")

        return "\n".join(lines)
