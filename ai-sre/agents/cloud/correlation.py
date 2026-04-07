"""Cross-layer correlation — shared library for AWS-to-K8s context enrichment.

Provides correlation logic used by all SRE agents to enrich their
Kubernetes-level investigations with AWS cloud context. Each agent
calls into this module to get relevant AWS data for the resources
they are investigating.

This module is the bridge that makes the AWS Cloud Agent's data
available to all specialist agents.
"""

import logging
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger(__name__)


@dataclass
class AWSNodeContext:
    """AWS context for a Kubernetes node."""

    node_name: str
    instance_id: str
    instance_type: str
    availability_zone: str
    lifecycle: str = "on-demand"  # on-demand, spot
    instance_status: str = "ok"  # ok, impaired, insufficient-data
    system_check: str = "ok"  # ok, impaired
    instance_check: str = "ok"  # ok, impaired
    scheduled_events: list[dict[str, str]] = field(default_factory=list)
    spot_interruption: bool = False
    spot_termination_time: Optional[str] = None


@dataclass
class AWSVolumeContext:
    """AWS context for a Kubernetes PVC."""

    pvc_name: str
    pvc_namespace: str
    volume_id: str
    volume_type: str
    volume_status: str = "ok"  # ok, impaired, warning
    io_performance: str = "normal"  # normal, degraded, severely-degraded
    iops: int = 0
    queue_length: float = 0.0


@dataclass
class AWSSecurityContext:
    """AWS security context for a cluster or instance."""

    guardduty_findings: list[dict[str, Any]] = field(default_factory=list)
    securityhub_findings: list[dict[str, Any]] = field(default_factory=list)
    cloudtrail_events: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class AWSQuotaContext:
    """AWS quota context for scaling decisions."""

    quotas_at_risk: list[dict[str, Any]] = field(default_factory=list)
    ec2_instance_headroom: dict[str, int] = field(default_factory=dict)
    ebs_headroom: dict[str, float] = field(default_factory=dict)


@dataclass
class CrossLayerEnrichment:
    """Aggregated AWS enrichment context for an investigation."""

    node_contexts: list[AWSNodeContext] = field(default_factory=list)
    volume_contexts: list[AWSVolumeContext] = field(default_factory=list)
    security_context: Optional[AWSSecurityContext] = None
    quota_context: Optional[AWSQuotaContext] = None
    network_issues: list[dict[str, Any]] = field(default_factory=list)
    correlation_notes: list[str] = field(default_factory=list)


class CrossLayerCorrelator:
    """Correlates AWS cloud events with Kubernetes-level signals.

    Used by specialist agents to enrich their investigations
    with cloud infrastructure context from the AWS Cloud Agent.
    """

    def __init__(self) -> None:
        self._node_cache: dict[str, AWSNodeContext] = {}
        self._volume_cache: dict[str, AWSVolumeContext] = {}

    async def enrich_for_node(
        self,
        node_name: str,
        cluster: str,
    ) -> Optional[AWSNodeContext]:
        """Get AWS context for a K8s node.

        In production, queries the AWS Cloud Agent's instance map
        and then calls aws-mcp for current status.

        Returns None if the node is not found or not an EC2 instance.
        """
        cached = self._node_cache.get(f"{cluster}/{node_name}")
        if cached:
            return cached

        # In production:
        # 1. Look up instance ID from cloud agent's instance_map
        # 2. Call aws-mcp: describe_instance_status for health
        # 3. Call aws-mcp: describe_spot_instance_requests if spot
        # 4. Build and cache the context
        return None

    async def enrich_for_pvc(
        self,
        pvc_name: str,
        namespace: str,
        cluster: str,
    ) -> Optional[AWSVolumeContext]:
        """Get AWS context for a K8s PVC.

        In production, queries the AWS Cloud Agent's volume map
        and then calls aws-mcp for current volume status.
        """
        cached = self._volume_cache.get(f"{cluster}/{namespace}/{pvc_name}")
        if cached:
            return cached

        # In production:
        # 1. Look up volume ID from cloud agent's volume_map
        # 2. Call aws-mcp: describe_volume_status for health
        # 3. Call aws-mcp: get_metric_data for IO metrics
        return None

    async def enrich_for_security(
        self,
        cluster: str,
        instance_ids: Optional[list[str]] = None,
    ) -> AWSSecurityContext:
        """Get security context for a cluster or specific instances.

        In production, queries GuardDuty, SecurityHub, and CloudTrail
        filtered to the relevant resources.
        """
        # In production:
        # 1. Call aws-mcp: get_guardduty_findings filtered by instance_ids
        # 2. Call aws-mcp: get_securityhub_findings for the cluster
        # 3. Call aws-mcp: lookup_events for recent IAM/SG changes
        return AWSSecurityContext()

    async def enrich_for_quotas(
        self,
        region: str,
        instance_types: Optional[list[str]] = None,
    ) -> AWSQuotaContext:
        """Get quota context for scaling decisions.

        Returns current quota utilization and headroom for
        the instance types and services relevant to scaling.
        """
        # In production:
        # 1. Call aws-mcp: get_service_quota for each monitored quota
        # 2. Calculate headroom per instance type
        return AWSQuotaContext()

    async def full_enrichment(
        self,
        cluster: str,
        node_names: Optional[list[str]] = None,
        pvc_names: Optional[list[tuple[str, str]]] = None,
    ) -> CrossLayerEnrichment:
        """Get full cross-layer enrichment for an investigation.

        This is the main entry point called by specialist agents.
        Aggregates node, volume, security, and network context.
        """
        enrichment = CrossLayerEnrichment()

        # Enrich nodes
        if node_names:
            for node in node_names:
                ctx = await self.enrich_for_node(node, cluster)
                if ctx:
                    enrichment.node_contexts.append(ctx)
                    # Add correlation notes
                    if ctx.instance_check == "impaired":
                        enrichment.correlation_notes.append(
                            f"EC2 instance check FAILING for node {node} "
                            f"({ctx.instance_id}) — likely hardware issue"
                        )
                    if ctx.system_check == "impaired":
                        enrichment.correlation_notes.append(
                            f"EC2 system check FAILING for node {node} "
                            f"({ctx.instance_id}) — AWS infrastructure issue"
                        )
                    if ctx.spot_interruption:
                        enrichment.correlation_notes.append(
                            f"Spot interruption notice for node {node} — "
                            f"termination at {ctx.spot_termination_time}"
                        )
                    if ctx.scheduled_events:
                        for event in ctx.scheduled_events:
                            enrichment.correlation_notes.append(
                                f"Scheduled maintenance for node {node}: "
                                f"{event.get('description', 'unknown')} "
                                f"at {event.get('not_before', 'TBD')}"
                            )

        # Enrich PVCs
        if pvc_names:
            for pvc_name, namespace in pvc_names:
                ctx = await self.enrich_for_pvc(pvc_name, namespace, cluster)
                if ctx:
                    enrichment.volume_contexts.append(ctx)
                    if ctx.volume_status == "impaired":
                        enrichment.correlation_notes.append(
                            f"EBS volume {ctx.volume_id} IMPAIRED for "
                            f"PVC {pvc_name} — IO errors expected"
                        )

        # Security context
        instance_ids = [
            nc.instance_id for nc in enrichment.node_contexts
        ]
        enrichment.security_context = await self.enrich_for_security(
            cluster, instance_ids or None
        )

        return enrichment

    def correlate_pod_crash_with_aws(
        self,
        node_context: Optional[AWSNodeContext],
        volume_context: Optional[AWSVolumeContext],
    ) -> list[str]:
        """Correlate a pod crash with AWS infrastructure state.

        Returns a list of correlation insights that help determine
        if the root cause is at the AWS level vs application level.
        """
        insights = []

        if node_context:
            if node_context.instance_check == "impaired":
                insights.append(
                    "ROOT CAUSE LIKELY AWS: EC2 instance check failing — "
                    "pod crash is secondary to instance health issue"
                )
            if node_context.system_check == "impaired":
                insights.append(
                    "ROOT CAUSE LIKELY AWS: EC2 system check failing — "
                    "AWS infrastructure issue affecting this host"
                )
            if node_context.spot_interruption:
                insights.append(
                    "ROOT CAUSE: Spot interruption — instance being reclaimed, "
                    "pod crash expected during termination"
                )
            if node_context.scheduled_events:
                insights.append(
                    "CONTRIBUTING FACTOR: EC2 scheduled maintenance may be "
                    "affecting instance stability"
                )

        if volume_context:
            if volume_context.volume_status == "impaired":
                insights.append(
                    "ROOT CAUSE LIKELY AWS: EBS volume impaired — "
                    "pod IO errors are caused by volume health, not application"
                )
            if volume_context.io_performance in ("degraded", "severely-degraded"):
                insights.append(
                    f"CONTRIBUTING FACTOR: EBS IO performance is "
                    f"{volume_context.io_performance} — "
                    f"may cause application timeouts"
                )

        if not insights:
            insights.append(
                "AWS infrastructure checks PASSING — "
                "root cause likely at application/K8s level"
            )

        return insights

    def correlate_gpu_issue_with_aws(
        self,
        node_context: Optional[AWSNodeContext],
    ) -> list[str]:
        """Correlate GPU health issues with AWS EC2 state.

        Helps distinguish between GPU hardware issues (AWS) and
        GPU driver/software issues (K8s/application).
        """
        insights = []

        if not node_context:
            insights.append(
                "No AWS context available for this node — "
                "cannot determine if issue is hardware vs software"
            )
            return insights

        if node_context.instance_check == "impaired":
            insights.append(
                "EC2 instance check FAILING — GPU errors likely caused by "
                "underlying hardware issue. Recommend filing AWS support ticket."
            )
        elif node_context.system_check == "impaired":
            insights.append(
                "EC2 system check FAILING — AWS infrastructure issue may be "
                "causing GPU instability. Monitor for recovery."
            )
        else:
            insights.append(
                "EC2 instance/system checks PASSING — GPU issue is likely "
                "driver or software related, not hardware."
            )

        if node_context.spot_interruption:
            insights.append(
                "SPOT INTERRUPTION pending — GPU errors may be related to "
                "impending instance termination. Prioritize checkpoint save."
            )

        if node_context.scheduled_events:
            insights.append(
                "Scheduled maintenance event on this instance — "
                "GPU issues may resolve after maintenance window."
            )

        return insights

    def correlate_network_timeout_with_aws(
        self,
        cluster: str,
        network_issues: list[dict[str, Any]],
    ) -> list[str]:
        """Correlate network timeouts with AWS networking state.

        Checks for TGW BGP session issues and VPC flow anomalies
        that could explain K8s-level network failures.
        """
        insights = []

        bgp_issues = [
            n for n in network_issues
            if n.get("event_type") == "bgp-session-down"
        ]
        if bgp_issues:
            insights.append(
                "ROOT CAUSE LIKELY AWS: TGW BGP session DOWN — "
                "network timeouts caused by lost BGP routes, not application"
            )

        flow_anomalies = [
            n for n in network_issues
            if n.get("event_type") == "flow-anomaly"
        ]
        if flow_anomalies:
            insights.append(
                "CONTRIBUTING FACTOR: VPC flow log anomalies detected — "
                "unusual traffic patterns may indicate network congestion"
            )

        if not insights:
            insights.append(
                "AWS networking checks PASSING — "
                "network timeouts likely at application/Cilium level"
            )

        return insights
