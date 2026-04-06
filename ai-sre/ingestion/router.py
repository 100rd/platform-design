"""Alert routing — maps alerts to specialized agent targets."""

import logging
from typing import Optional

from .models import AlertRouteTarget

logger = logging.getLogger(__name__)

# Routing rules: prefix patterns to agent targets
ROUTING_RULES: list[tuple[list[str], AlertRouteTarget]] = [
    (["gpu_", "dcgm_"], AlertRouteTarget.GPU_HEALTH),
    (["kube_pod_", "container_"], AlertRouteTarget.INCIDENT_RESPONSE),
    (["node_", "kubelet_"], AlertRouteTarget.CAPACITY_PLANNING),
    (["cilium_", "network_"], AlertRouteTarget.INCIDENT_RESPONSE),
    (["vllm_"], AlertRouteTarget.PREDICTIVE_SCALING),
    (["cost_"], AlertRouteTarget.COST_OPTIMIZATION),
]


def route_alert(
    alertname: str,
    labels: Optional[dict[str, str]] = None,
) -> AlertRouteTarget:
    """Determine which specialized agent should handle an alert.

    Routes based on alert name prefix patterns. Falls back to
    the On-Call Copilot for unrecognized alert types.
    """
    lower_name = alertname.lower()

    for prefixes, target in ROUTING_RULES:
        if any(lower_name.startswith(prefix) for prefix in prefixes):
            logger.info("Routing '%s' -> %s", alertname, target.value)
            return target

    # Check severity-based override
    if labels:
        severity = labels.get("severity", "")
        if severity == "critical":
            logger.info(
                "Critical alert '%s' with no specific route -> incident-response",
                alertname,
            )
            return AlertRouteTarget.INCIDENT_RESPONSE

    logger.info("No specific route for '%s' -> oncall-copilot", alertname)
    return AlertRouteTarget.ONCALL_COPILOT
