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
- Design AWS-level chaos scenarios for cloud infrastructure resilience

Experiment categories:
1. Pod failure: kill pods, restart containers
2. Node failure: cordon/drain nodes, simulate node loss
3. Network: inject latency, partition, DNS failure
4. Resource: CPU/memory stress, disk fill
5. Cluster: API server degradation, etcd latency
6. GPU-specific: GPU device failure, NVLink degradation, driver crash
7. AWS-level: AZ failure, TGW Connect failure, EBS detach, spot interruption

AWS-level chaos scenarios:
- Simulate AZ failure: what happens if us-east-1a goes down?
- Simulate TGW Connect failure: what happens to BGP routing?
- Simulate EBS detach: will StatefulSets recover correctly?
- Simulate spot interruption: do checkpoints save in time?
- Simulate security group change: does NetworkPolicy isolation hold?

Pre-chaos AWS validation:
- Verify AWS account has permissions for the experiment
- Check capacity in other AZs for AZ failure simulation
- Verify PDBs and anti-affinity before node failure tests
- Confirm backup/snapshot state before EBS experiments

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
    category: str  # pod, node, network, resource, cluster, gpu, aws
    target_cluster: str
    target_namespace: Optional[str] = None
    description: str = ""
    hypothesis: str = ""
    blast_radius: str = ""
    expected_impact: str = ""
    rollback_procedure: str = ""
    prerequisites: list[str] = field(default_factory=list)
    aws_prerequisites: list[str] = field(default_factory=list)
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
    """Chaos Engineering Agent — recommends resilience tests.

    Enhanced with AWS-level chaos scenarios that test cloud
    infrastructure resilience beyond the Kubernetes layer.
    """

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

        # AWS-level chaos experiments
        experiments.append(ChaosExperiment(
            name="az-failure-simulation",
            category="aws",
            target_cluster=cluster,
            description=(
                "Simulate AZ failure by cordoning all nodes in a single AZ. "
                "Tests cross-AZ redundancy and topology spread constraints."
            ),
            hypothesis=(
                "All critical services remain available with degraded capacity. "
                "Karpenter provisions replacement nodes in remaining AZs."
            ),
            blast_radius=(
                "All pods on nodes in the target AZ. "
                "Cross-AZ data transfer may increase."
            ),
            rollback_procedure="Uncordon all nodes in the target AZ",
            prerequisites=[
                "Ensure spare capacity in other AZs",
                "Verify PDBs allow loss of one AZ worth of replicas",
                "Check topology spread constraints are configured",
            ],
            aws_prerequisites=[
                "Verify EC2 capacity available in remaining AZs",
                "Check Karpenter NodePool allows multi-AZ provisioning",
            ],
            duration_minutes=30,
            risk_level="high",
        ))

        experiments.append(ChaosExperiment(
            name="tgw-connect-failure",
            category="aws",
            target_cluster=cluster,
            description=(
                "Simulate TGW Connect peer failure to test BGP routing resilience. "
                "Verifies Cilium handles route withdrawal gracefully."
            ),
            hypothesis=(
                "Traffic fails over to alternate BGP peer within 30 seconds. "
                "No persistent network disruption for workloads."
            ),
            blast_radius=(
                "Pod-to-pod networking across clusters may be disrupted "
                "until BGP convergence completes."
            ),
            rollback_procedure="Re-establish TGW Connect peer session",
            prerequisites=[
                "Ensure redundant BGP peers are configured",
                "Verify Cilium BGP peering has backup routes",
            ],
            aws_prerequisites=[
                "Verify TGW Connect has multiple peers",
                "Check BGP hold timer settings",
            ],
            duration_minutes=15,
            risk_level="high",
        ))

        experiments.append(ChaosExperiment(
            name="ebs-detach-simulation",
            category="aws",
            target_cluster=cluster,
            description=(
                "Simulate EBS volume detach to test StatefulSet recovery. "
                "Verifies PVC re-attachment and data integrity."
            ),
            hypothesis=(
                "StatefulSet pod detects IO failure, restarts, "
                "and re-attaches PVC within 5 minutes."
            ),
            blast_radius="Single StatefulSet pod with the target PVC",
            rollback_procedure="Force re-attach EBS volume to the instance",
            prerequisites=[
                "Target a non-critical StatefulSet in staging first",
                "Ensure recent EBS snapshot exists",
            ],
            aws_prerequisites=[
                "Verify EBS snapshot is current (< 1 hour old)",
                "Confirm volume is not io2 with Multi-Attach",
            ],
            duration_minutes=10,
            risk_level="high",
        ))

        experiments.append(ChaosExperiment(
            name="spot-interruption-simulation",
            category="aws",
            target_cluster=cluster,
            description=(
                "Simulate spot interruption using FIS to test graceful migration. "
                "Verifies checkpoint save and Karpenter replacement timing."
            ),
            hypothesis=(
                "Training job saves checkpoint within 2 minutes. "
                "Karpenter provisions replacement node within 4 minutes. "
                "Job resumes from checkpoint without data loss."
            ),
            blast_radius="Single spot instance and its pods",
            rollback_procedure="Karpenter auto-provisions replacement",
            prerequisites=[
                "Ensure checkpoint mechanism is configured for workloads",
                "Verify Karpenter has capacity for replacement",
            ],
            aws_prerequisites=[
                "AWS FIS experiment template configured",
                "IAM role for FIS with ec2:SendSpotInstanceInterruptions",
            ],
            duration_minutes=15,
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

        # AWS-level resilience gaps
        gaps.append(ResilienceGap(
            area="no-spot-checkpoint",
            description=(
                "GPU training jobs on spot instances lack checkpoint mechanism — "
                "spot interruption causes full restart"
            ),
            severity="high",
            affected_services=["pytorch-training", "gpu-inference"],
            recommended_experiment="spot-interruption-simulation",
            remediation=(
                "Implement periodic checkpointing for all training jobs. "
                "Configure SIGTERM handler for graceful checkpoint on interruption."
            ),
        ))

        gaps.append(ResilienceGap(
            area="single-bgp-peer",
            description=(
                "TGW Connect has single BGP peer per cluster — "
                "peer failure causes network isolation"
            ),
            severity="high",
            affected_services=["cross-cluster-networking"],
            recommended_experiment="tgw-connect-failure",
            remediation=(
                "Add redundant TGW Connect peers with separate attachments. "
                "Configure BFD for faster failure detection."
            ),
        ))

        gaps.append(ResilienceGap(
            area="no-ebs-snapshot-policy",
            description=(
                "StatefulSet EBS volumes lack automated snapshot policy — "
                "volume failure causes data loss"
            ),
            severity="medium",
            affected_services=["stateful-workloads"],
            recommended_experiment="ebs-detach-simulation",
            remediation=(
                "Configure AWS DLM (Data Lifecycle Manager) for automated "
                "EBS snapshots every 6 hours for critical volumes."
            ),
        ))

        return gaps
