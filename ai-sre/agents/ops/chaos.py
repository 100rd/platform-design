"""Chaos Engineering Agent — resilience testing recommendations and blast radius analysis."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are a Chaos Engineering specialist for a multi-cluster Kubernetes platform.

Your capabilities:
- Suggest chaos experiments based on system topology and dependencies
- Analyze blast radius of potential failures
- Review resilience gaps in the architecture
- Recommend improvements based on chaos test results
- Design game days for the engineering team

Experiment categories:
1. Pod failure: kill pods, restart containers
2. Node failure: cordon/drain nodes, simulate node loss
3. Network: inject latency, partition, DNS failure
4. Resource: CPU/memory stress, disk fill
5. Cluster: API server degradation, etcd latency
6. GPU-specific: GPU device failure, NVLink degradation, driver crash

Constraints:
- NEVER execute chaos experiments autonomously
- All experiments require explicit human approval via Slack
- Always define blast radius before suggesting experiments
- Recommend starting with non-production environments
- Include rollback procedures for every experiment
"""


@dataclass
class ChaosExperiment:
    """A proposed chaos experiment."""

    name: str
    category: str
    target_cluster: str
    target_namespace: Optional[str] = None
    description: str = ""
    hypothesis: str = ""
    blast_radius: str = ""
    expected_impact: str = ""
    rollback_procedure: str = ""
    prerequisites: list[str] = field(default_factory=list)
    duration_minutes: int = 5
    risk_level: str = "medium"


@dataclass
class ResilienceGap:
    """An identified gap in system resilience."""

    area: str
    description: str
    severity: str = "medium"
    affected_services: list[str] = field(default_factory=list)
    recommended_experiment: Optional[str] = None
    remediation: str = ""


@dataclass
class ChaosAdvisory:
    """Chaos engineering advisory."""

    cluster: str
    experiments: list[ChaosExperiment] = field(default_factory=list)
    resilience_gaps: list[ResilienceGap] = field(default_factory=list)
    game_day_plan: Optional[str] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


class ChaosEngineeringAgent:
    """Chaos Engineering Agent — recommends resilience tests."""

    def __init__(self) -> None:
        self.experiments_history: list[ChaosExperiment] = []

    async def analyze_resilience(self, cluster: str) -> ChaosAdvisory:
        """Analyze cluster resilience and suggest experiments."""
        advisory = ChaosAdvisory(cluster=cluster)
        # In production, examines topology, PDBs, replica counts
        return advisory

    def suggest_experiments(
        self,
        cluster: str,
        topology: dict[str, Any],
    ) -> list[ChaosExperiment]:
        """Generate experiment suggestions based on cluster topology."""
        experiments = []

        # Standard experiments for any cluster
        experiments.append(ChaosExperiment(
            name="pod-failure-critical-service",
            category="pod",
            target_cluster=cluster,
            description="Kill pods of a critical service to verify PDB and self-healing",
            hypothesis="Service recovers within 30 seconds with no user impact",
            blast_radius="Single service, affected by PDB minAvailable",
            rollback_procedure="Pods auto-restart via Deployment controller",
            duration_minutes=5,
            risk_level="low",
        ))

        experiments.append(ChaosExperiment(
            name="node-failure-simulation",
            category="node",
            target_cluster=cluster,
            description="Cordon and drain a worker node to simulate node failure",
            hypothesis="Workloads reschedule to other nodes within 2 minutes",
            blast_radius="All pods on target node; depends on PDB configuration",
            rollback_procedure="Uncordon node: kubectl uncordon <node>",
            prerequisites=["Ensure spare capacity for rescheduling"],
            duration_minutes=10,
            risk_level="medium",
        ))

        experiments.append(ChaosExperiment(
            name="network-latency-injection",
            category="network",
            target_cluster=cluster,
            description="Inject 100ms latency between services to test timeout handling",
            hypothesis="Services degrade gracefully with increased latency, no cascading failures",
            blast_radius="Inter-service communication in target namespace",
            rollback_procedure="Remove Cilium network policy / tc rules",
            duration_minutes=5,
            risk_level="medium",
        ))

        return experiments

    def identify_resilience_gaps(
        self,
        topology: dict[str, Any],
    ) -> list[ResilienceGap]:
        """Identify resilience gaps from topology analysis."""
        gaps = []

        # Common gaps to check
        gaps.append(ResilienceGap(
            area="single-az-deployment",
            description="Critical services deployed in single AZ lack cross-AZ redundancy",
            severity="high",
            recommended_experiment="az-failure-simulation",
            remediation="Configure topology spread constraints for cross-AZ distribution",
        ))

        gaps.append(ResilienceGap(
            area="missing-pdb",
            description="Some deployments lack PodDisruptionBudgets",
            severity="medium",
            recommended_experiment="pod-failure-critical-service",
            remediation="Add PDB with minAvailable for all critical services",
        ))

        return gaps
