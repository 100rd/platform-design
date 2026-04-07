"""AWS Cloud Agent — EC2/EBS/Network/Security/Quota monitoring and advisory."""

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

logger = logging.getLogger(__name__)

SYSTEM_PROMPT = """You are an AWS Cloud Infrastructure specialist for a multi-cluster
Kubernetes platform (platform, gpu-inference, blockchain, gpu-analysis) running on EKS.

Your capabilities:
- Monitor EC2 instance health: scheduled events, status checks, spot interruptions
- Monitor EBS volume health: impairment, IO performance, queue length
- Monitor VPC/TGW networking: BGP sessions, flow logs, ENI health
- Analyze security findings: GuardDuty, SecurityHub, CloudTrail anomalies
- Track service quotas: EC2, EBS, VPC, EKS limits vs current usage
- Ingest and route CloudWatch alarms alongside Alertmanager alerts

Cross-layer correlation — you bridge AWS and Kubernetes:
- EC2 instance ID <-> K8s node name mapping
- EBS volume ID <-> PVC <-> Pod mapping
- Security finding <-> affected cluster/service mapping
- Service quota <-> scaling headroom mapping

Key AWS APIs you use (read-only):
- ec2:DescribeInstanceStatus — scheduled events, system/instance checks
- ec2:DescribeSpotInstanceRequests — spot interruption warnings
- ec2:DescribeVolumes, ec2:DescribeVolumeStatus — EBS health
- ec2:DescribeTransitGatewayConnectPeers — BGP session state
- ec2:DescribeFlowLogs, logs:FilterLogEvents — VPC flow log insights
- ec2:DescribeNetworkInterfaces — ENI health
- guardduty:GetFindings, guardduty:ListFindings — security findings
- securityhub:GetFindings — compliance check failures
- cloudtrail:LookupEvents — recent IAM/SG/KMS changes
- servicequotas:GetServiceQuota — current vs limit
- cloudwatch:DescribeAlarms, cloudwatch:GetMetricData — alarm state

Thresholds:
- Service quota > 80% utilization: alert
- Spot interruption notice: immediate advisory (2 min window)
- EC2 scheduled maintenance: advisory 48h before window
- GuardDuty HIGH/CRITICAL: immediate security advisory
- EBS volume impaired: immediate advisory
- TGW BGP session not ESTABLISHED: immediate advisory

Constraints:
- Advisory-only: never execute commands or modify AWS resources
- Read-only IAM policy: ec2:Describe*, cloudwatch:Get*, guardduty:Get*, etc.
- Always include K8s impact when reporting AWS-level events
- Escalate security findings with full context to incident response
"""


# --- Data Models ---


@dataclass
class EC2InstanceMapping:
    """Mapping between EC2 instance and K8s node."""

    instance_id: str
    node_name: str
    cluster: str
    instance_type: str
    availability_zone: str
    lifecycle: str = "on-demand"  # on-demand, spot
    launch_time: Optional[str] = None


@dataclass
class EC2HealthEvent:
    """An EC2 health or maintenance event."""

    instance_id: str
    node_name: str
    cluster: str
    event_type: str  # scheduled-maintenance, spot-interruption, instance-stop, system-reboot
    description: str
    not_before: Optional[str] = None
    not_after: Optional[str] = None
    status_checks: dict[str, str] = field(default_factory=dict)


@dataclass
class EBSVolumeMapping:
    """Mapping between EBS volume and K8s PVC/Pod."""

    volume_id: str
    pvc_name: str
    pvc_namespace: str
    pod_name: str
    cluster: str
    volume_type: str = ""
    iops: int = 0
    status: str = "ok"  # ok, impaired, warning


@dataclass
class EBSHealthEvent:
    """An EBS volume health event."""

    volume_id: str
    pvc_name: str
    pod_name: str
    cluster: str
    status: str  # ok, impaired, warning
    io_performance: str = ""  # normal, degraded, severely-degraded
    queue_length: float = 0.0
    description: str = ""


@dataclass
class NetworkEvent:
    """A VPC/TGW networking event."""

    event_type: str  # bgp-session-down, flow-anomaly, eni-unhealthy
    cluster: str
    resource_id: str
    description: str
    bgp_state: Optional[str] = None
    peer_address: Optional[str] = None
    severity: str = "warning"


@dataclass
class SecurityFinding:
    """A security finding from GuardDuty or SecurityHub."""

    source: str  # guardduty, securityhub, cloudtrail
    finding_id: str
    severity: str  # LOW, MEDIUM, HIGH, CRITICAL
    title: str
    description: str
    affected_resources: list[str] = field(default_factory=list)
    affected_cluster: Optional[str] = None
    recommended_actions: list[str] = field(default_factory=list)
    first_seen: Optional[str] = None


@dataclass
class QuotaStatus:
    """Service quota utilization status."""

    service: str
    quota_name: str
    region: str
    current_value: float
    limit_value: float
    utilization_pct: float
    unit: str = ""
    at_risk: bool = False


@dataclass
class CloudAdvisory:
    """Consolidated advisory from the AWS Cloud Agent."""

    advisory_type: str  # spot-interruption, maintenance, ebs-impairment,
    # security, quota, bgp-down, cloudwatch-alarm
    severity: str  # info, warning, critical
    title: str
    cluster: str
    description: str
    aws_context: dict[str, Any] = field(default_factory=dict)
    k8s_impact: list[str] = field(default_factory=list)
    recommended_actions: list[str] = field(default_factory=list)
    estimated_impact: Optional[str] = None
    timestamp: str = field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )


# --- Quota thresholds ---

QUOTA_ALERT_THRESHOLD = 80.0  # percent

# Service quotas to monitor
MONITORED_QUOTAS: list[dict[str, str]] = [
    {"service": "ec2", "quota": "Running On-Demand Standard instances"},
    {"service": "ec2", "quota": "Running On-Demand P instances"},
    {"service": "ec2", "quota": "Running On-Demand G and VT instances"},
    {"service": "ec2", "quota": "EC2-VPC Elastic IPs"},
    {"service": "ec2", "quota": "Network interfaces per Region"},
    {"service": "ebs", "quota": "Storage for gp3 volumes, in TiB"},
    {"service": "ebs", "quota": "Storage for io2 volumes, in TiB"},
    {"service": "ebs", "quota": "IOPS for provisioned IOPS SSD (io2) volumes"},
    {"service": "vpc", "quota": "Routes per route table"},
    {"service": "vpc", "quota": "Security groups per network interface"},
    {"service": "eks", "quota": "Nodes per managed node group"},
]


class AWSCloudAgent:
    """AWS Cloud Agent — monitors cloud infrastructure and generates advisories.

    Uses aws-mcp for AWS API calls, metrics-mcp for CloudWatch data,
    and kubernetes-mcp for node/PVC mapping lookups.
    """

    def __init__(self) -> None:
        self.instance_map: dict[str, EC2InstanceMapping] = {}
        self.volume_map: dict[str, EBSVolumeMapping] = {}
        self.active_advisories: list[CloudAdvisory] = []
        self.quota_status: list[QuotaStatus] = []

    # --- EC2 Health ---

    async def check_ec2_health(
        self,
        cluster: Optional[str] = None,
    ) -> list[EC2HealthEvent]:
        """Check EC2 instance health across the fleet.

        In production, calls aws-mcp:
        - describe_instance_status for scheduled events and status checks
        - describe_spot_instance_requests for interruption notices

        Returns list of health events requiring attention.
        """
        events: list[EC2HealthEvent] = []
        # In production, iterate over instance_map and query AWS APIs
        # Filter to instances belonging to target cluster if specified
        return events

    async def check_spot_interruptions(self) -> list[CloudAdvisory]:
        """Check for spot instance interruption notices.

        Spot interruptions give a 2-minute warning. This must be
        checked frequently (every 30s) and immediately generate
        advisories for checkpoint saves and workload migration.
        """
        advisories: list[CloudAdvisory] = []
        # In production, queries EC2 metadata or EventBridge for
        # spot interruption warnings, generates urgent advisories
        return advisories

    async def check_maintenance_events(self) -> list[CloudAdvisory]:
        """Check for upcoming EC2 scheduled maintenance.

        Generates advisories for maintenance windows so nodes can
        be proactively drained before the maintenance occurs.
        """
        advisories: list[CloudAdvisory] = []
        # In production, queries describe_instance_status for
        # scheduledEvents and generates advisories 48h ahead
        return advisories

    # --- EBS Health ---

    async def check_ebs_health(
        self,
        cluster: Optional[str] = None,
    ) -> list[EBSHealthEvent]:
        """Check EBS volume health.

        In production, calls aws-mcp:
        - describe_volume_status for impairment
        - cloudwatch get_metric_data for IO metrics

        Correlates volume IDs to PVCs and pods via volume_map.
        """
        events: list[EBSHealthEvent] = []
        return events

    # --- Networking ---

    async def check_tgw_bgp_sessions(self) -> list[NetworkEvent]:
        """Check Transit Gateway Connect peer BGP session states.

        Critical for gpu-inference cluster which uses TGW Connect
        with BGP for high-performance networking via Cilium.
        """
        events: list[NetworkEvent] = []
        # In production, calls describe_transit_gateway_connect_peers
        # and alerts if any BGP session is not in ESTABLISHED state
        return events

    async def check_vpc_flow_anomalies(
        self,
        cluster: Optional[str] = None,
    ) -> list[NetworkEvent]:
        """Analyze VPC flow logs for anomalies.

        Looks for unusual patterns: top talkers, rejected flows,
        unexpected cross-AZ traffic spikes.
        """
        events: list[NetworkEvent] = []
        return events

    # --- Security ---

    async def check_guardduty_findings(self) -> list[SecurityFinding]:
        """Retrieve active GuardDuty findings.

        Filters for new and active findings, prioritizing HIGH and
        CRITICAL severity. Maps affected resources to clusters.
        """
        findings: list[SecurityFinding] = []
        return findings

    async def check_securityhub_findings(self) -> list[SecurityFinding]:
        """Retrieve SecurityHub compliance failures.

        Focuses on failed checks that affect EKS clusters and
        supporting infrastructure (VPC, IAM, S3).
        """
        findings: list[SecurityFinding] = []
        return findings

    async def check_cloudtrail_anomalies(self) -> list[SecurityFinding]:
        """Check CloudTrail for suspicious API activity.

        Monitors for IAM changes, security group modifications,
        KMS key usage, and credential exfiltration indicators.
        """
        findings: list[SecurityFinding] = []
        return findings

    # --- Service Quotas ---

    async def check_service_quotas(self) -> list[QuotaStatus]:
        """Check all monitored service quotas.

        Returns quotas that exceed the alert threshold (80%).
        """
        at_risk: list[QuotaStatus] = []
        # In production, queries service quotas API for each
        # entry in MONITORED_QUOTAS and calculates utilization
        return at_risk

    def evaluate_quota(
        self,
        service: str,
        quota_name: str,
        region: str,
        current: float,
        limit: float,
        unit: str = "",
    ) -> QuotaStatus:
        """Evaluate a single service quota against threshold."""
        utilization = (current / limit * 100) if limit > 0 else 0
        status = QuotaStatus(
            service=service,
            quota_name=quota_name,
            region=region,
            current_value=current,
            limit_value=limit,
            utilization_pct=round(utilization, 1),
            unit=unit,
            at_risk=utilization >= QUOTA_ALERT_THRESHOLD,
        )
        self.quota_status.append(status)
        return status

    # --- CloudWatch Alarms ---

    async def check_cloudwatch_alarms(self) -> list[CloudAdvisory]:
        """Retrieve active CloudWatch alarms and route them as advisories.

        CloudWatch alarms are treated as an additional alert source
        alongside Alertmanager, going through the same ingestion pipeline.
        """
        advisories: list[CloudAdvisory] = []
        return advisories

    # --- EC2 <-> K8s Mapping ---

    async def refresh_instance_map(self, cluster: str) -> None:
        """Refresh the EC2 instance to K8s node mapping for a cluster.

        In production, queries:
        - kubernetes-mcp: list_nodes to get node names and provider IDs
        - aws-mcp: describe_instances to get instance details

        The provider ID on K8s nodes contains the EC2 instance ID:
        aws:///us-east-1a/i-0abc123def456
        """
        # In production, builds the instance_map from K8s node provider IDs
        pass

    async def refresh_volume_map(self, cluster: str) -> None:
        """Refresh the EBS volume to PVC/Pod mapping for a cluster.

        In production, queries:
        - kubernetes-mcp: list_persistent_volumes, list_persistent_volume_claims
        - Maps PV.spec.csi.volumeHandle -> EBS volume ID
        - Traces PVC -> Pod via volume mounts
        """
        pass

    def get_node_for_instance(self, instance_id: str) -> Optional[EC2InstanceMapping]:
        """Look up the K8s node for an EC2 instance."""
        return self.instance_map.get(instance_id)

    def get_instances_for_cluster(self, cluster: str) -> list[EC2InstanceMapping]:
        """Get all EC2 instances belonging to a cluster."""
        return [
            m for m in self.instance_map.values()
            if m.cluster == cluster
        ]

    # --- Full Scan ---

    async def full_scan(
        self,
        cluster: Optional[str] = None,
    ) -> list[CloudAdvisory]:
        """Run a full cloud infrastructure scan.

        Checks all subsystems and generates advisories for any
        issues found. This is the main entry point called by
        the orchestrator on a periodic schedule.
        """
        advisories: list[CloudAdvisory] = []

        # Refresh mappings
        clusters = (
            [cluster] if cluster
            else ["platform", "gpu-inference", "blockchain", "gpu-analysis"]
        )
        for c in clusters:
            await self.refresh_instance_map(c)
            await self.refresh_volume_map(c)

        # Check all subsystems
        ec2_events = await self.check_ec2_health(cluster)
        for event in ec2_events:
            advisories.append(self._ec2_event_to_advisory(event))

        spot_advisories = await self.check_spot_interruptions()
        advisories.extend(spot_advisories)

        maintenance_advisories = await self.check_maintenance_events()
        advisories.extend(maintenance_advisories)

        ebs_events = await self.check_ebs_health(cluster)
        for event in ebs_events:
            advisories.append(self._ebs_event_to_advisory(event))

        network_events = await self.check_tgw_bgp_sessions()
        network_events.extend(await self.check_vpc_flow_anomalies(cluster))
        for event in network_events:
            advisories.append(self._network_event_to_advisory(event))

        security_findings = await self.check_guardduty_findings()
        security_findings.extend(await self.check_securityhub_findings())
        security_findings.extend(await self.check_cloudtrail_anomalies())
        for finding in security_findings:
            advisories.append(self._security_finding_to_advisory(finding))

        quota_risks = await self.check_service_quotas()
        for quota in quota_risks:
            advisories.append(self._quota_to_advisory(quota))

        cloudwatch_advisories = await self.check_cloudwatch_alarms()
        advisories.extend(cloudwatch_advisories)

        self.active_advisories = advisories
        return advisories

    # --- Advisory Builders ---

    def _ec2_event_to_advisory(self, event: EC2HealthEvent) -> CloudAdvisory:
        """Convert an EC2 health event to a CloudAdvisory."""
        severity = "critical" if event.event_type == "spot-interruption" else "warning"

        k8s_impact = [
            f"K8s node: {event.node_name}",
            f"Cluster: {event.cluster}",
        ]

        actions = []
        if event.event_type == "spot-interruption":
            actions = [
                f"URGENT: Trigger checkpoint save for workloads on {event.node_name}",
                f"Cordon node immediately: kubectl cordon {event.node_name}",
                "Karpenter will provision replacement (ETA: ~4 min)",
            ]
        elif event.event_type in ("scheduled-maintenance", "system-reboot"):
            actions = [
                f"Before maintenance window: kubectl cordon {event.node_name}",
                f"Drain node: kubectl drain {event.node_name} --ignore-daemonsets",
                "Verify PDB allows drain (check replica counts)",
                "After reboot: uncordon and verify health",
            ]

        return CloudAdvisory(
            advisory_type=event.event_type,
            severity=severity,
            title=f"EC2 {event.event_type}: {event.node_name} ({event.cluster})",
            cluster=event.cluster,
            description=event.description,
            aws_context={
                "instance_id": event.instance_id,
                "event_type": event.event_type,
                "not_before": event.not_before,
                "not_after": event.not_after,
                "status_checks": event.status_checks,
            },
            k8s_impact=k8s_impact,
            recommended_actions=actions,
        )

    def _ebs_event_to_advisory(self, event: EBSHealthEvent) -> CloudAdvisory:
        """Convert an EBS health event to a CloudAdvisory."""
        return CloudAdvisory(
            advisory_type="ebs-impairment",
            severity="critical" if event.status == "impaired" else "warning",
            title=f"EBS {event.status}: {event.volume_id} ({event.cluster})",
            cluster=event.cluster,
            description=event.description or (
                f"EBS volume {event.volume_id} is {event.status}. "
                f"IO performance: {event.io_performance}. "
                f"Queue length: {event.queue_length}"
            ),
            aws_context={
                "volume_id": event.volume_id,
                "status": event.status,
                "io_performance": event.io_performance,
                "queue_length": event.queue_length,
            },
            k8s_impact=[
                f"PVC: {event.pvc_name}",
                f"Pod: {event.pod_name}",
                f"Cluster: {event.cluster}",
            ],
            recommended_actions=[
                f"Check pod {event.pod_name} for IO errors",
                "If impaired: consider migrating workload to node with healthy volume",
                "If queue_length > 100: IO bottleneck, consider io2 volume upgrade",
            ],
        )

    def _network_event_to_advisory(self, event: NetworkEvent) -> CloudAdvisory:
        """Convert a network event to a CloudAdvisory."""
        actions = []
        if event.event_type == "bgp-session-down":
            actions = [
                "Check Cilium connectivity on affected cluster",
                "Verify TGW Connect peer configuration",
                f"BGP peer: {event.peer_address or 'unknown'}",
                "If persistent: check AWS TGW service health dashboard",
            ]

        return CloudAdvisory(
            advisory_type=event.event_type,
            severity=event.severity,
            title=f"Network: {event.event_type} ({event.cluster})",
            cluster=event.cluster,
            description=event.description,
            aws_context={
                "resource_id": event.resource_id,
                "bgp_state": event.bgp_state,
                "peer_address": event.peer_address,
            },
            k8s_impact=[
                f"Cluster: {event.cluster}",
                "Pod networking may be affected if BGP routes are lost",
            ],
            recommended_actions=actions,
        )

    def _security_finding_to_advisory(self, finding: SecurityFinding) -> CloudAdvisory:
        """Convert a security finding to a CloudAdvisory."""
        severity = "critical" if finding.severity in ("HIGH", "CRITICAL") else "warning"

        return CloudAdvisory(
            advisory_type="security",
            severity=severity,
            title=f"Security [{finding.source}]: {finding.title}",
            cluster=finding.affected_cluster or "unknown",
            description=finding.description,
            aws_context={
                "source": finding.source,
                "finding_id": finding.finding_id,
                "severity": finding.severity,
                "affected_resources": finding.affected_resources,
                "first_seen": finding.first_seen,
            },
            k8s_impact=[
                f"Affected cluster: {finding.affected_cluster or 'TBD'}",
                "Review pods on affected instances for unauthorized activity",
            ],
            recommended_actions=finding.recommended_actions or [
                "Investigate affected resources",
                "Check CloudTrail for related API activity",
                "Escalate to security team if HIGH/CRITICAL",
            ],
        )

    def _quota_to_advisory(self, quota: QuotaStatus) -> CloudAdvisory:
        """Convert a quota status to a CloudAdvisory."""
        return CloudAdvisory(
            advisory_type="quota",
            severity="warning",
            title=(
                f"Quota: {quota.service}/{quota.quota_name} "
                f"at {quota.utilization_pct}%"
            ),
            cluster="all",
            description=(
                f"Service quota {quota.quota_name} ({quota.service}) in "
                f"{quota.region} is at {quota.utilization_pct}% utilization: "
                f"{quota.current_value}/{quota.limit_value} {quota.unit}"
            ),
            aws_context={
                "service": quota.service,
                "quota_name": quota.quota_name,
                "region": quota.region,
                "current": quota.current_value,
                "limit": quota.limit_value,
                "utilization_pct": quota.utilization_pct,
            },
            k8s_impact=[
                "Scaling operations may fail if quota is exhausted",
                "Karpenter node provisioning will be blocked",
            ],
            recommended_actions=[
                f"Request quota increase for {quota.quota_name} in {quota.region}",
                "Review current resource usage for optimization opportunities",
                "Consider multi-region distribution if single-region constrained",
            ],
        )

    # --- Slack Formatting ---

    def format_slack_advisory(self, advisory: CloudAdvisory) -> str:
        """Format a cloud advisory as a Slack message."""
        severity_label = {
            "critical": "RED",
            "warning": "YELLOW",
            "info": "INFO",
        }

        lines = [
            f"AWS CLOUD ADVISORY: {advisory.title}",
            f"Severity: {severity_label.get(advisory.severity, 'INFO')}",
            "",
            f"Description: {advisory.description}",
            "",
        ]

        if advisory.k8s_impact:
            lines.append("K8s Impact:")
            for impact in advisory.k8s_impact:
                lines.append(f"  - {impact}")
            lines.append("")

        if advisory.recommended_actions:
            lines.append("Recommended Actions:")
            for i, action in enumerate(advisory.recommended_actions, 1):
                lines.append(f"  {i}. {action}")

        if advisory.estimated_impact:
            lines.extend(["", f"Estimated Impact: {advisory.estimated_impact}"])

        return "\n".join(lines)
