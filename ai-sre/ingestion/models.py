"""Data models for alert ingestion pipeline."""

from datetime import datetime
from enum import Enum
from typing import Any, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class AlertStatus(str, Enum):
    """Alert lifecycle status."""

    FIRING = "firing"
    INVESTIGATING = "investigating"
    ADVISED = "advised"
    RESOLVED = "resolved"


class AlertSeverity(str, Enum):
    """Alert severity levels."""

    CRITICAL = "critical"
    WARNING = "warning"
    INFO = "info"


class AlertmanagerAlert(BaseModel):
    """Single alert from Alertmanager webhook payload."""

    status: str
    labels: dict[str, str] = Field(default_factory=dict)
    annotations: dict[str, str] = Field(default_factory=dict)
    startsAt: str = ""
    endsAt: str = ""
    generatorURL: str = ""
    fingerprint: str = ""


class AlertmanagerWebhook(BaseModel):
    """Alertmanager webhook payload format.

    Compatible with both VictoriaMetrics VMAlertmanager and Prometheus Alertmanager.
    """

    version: str = "4"
    groupKey: str = ""
    truncatedAlerts: int = 0
    status: str = "firing"
    receiver: str = ""
    groupLabels: dict[str, str] = Field(default_factory=dict)
    commonLabels: dict[str, str] = Field(default_factory=dict)
    commonAnnotations: dict[str, str] = Field(default_factory=dict)
    externalURL: str = ""
    alerts: list[AlertmanagerAlert] = Field(default_factory=list)


class EnrichedAlert(BaseModel):
    """Alert enriched with contextual data for agent processing."""

    alert_id: UUID = Field(default_factory=uuid4)
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    alertname: str
    cluster: str = "unknown"
    namespace: Optional[str] = None
    severity: AlertSeverity = AlertSeverity.WARNING
    status: AlertStatus = AlertStatus.FIRING
    labels: dict[str, str] = Field(default_factory=dict)
    annotations: dict[str, str] = Field(default_factory=dict)
    fingerprint: str = ""
    enrichment_data: dict[str, Any] = Field(default_factory=dict)
    agent_advisory: Optional[str] = None
    resolution: Optional[str] = None
    ttfr_seconds: Optional[float] = None
    dedup_group: Optional[str] = None


class AlertRouteTarget(str, Enum):
    """Agent targets for alert routing."""

    GPU_HEALTH = "gpu-health"
    INCIDENT_RESPONSE = "incident-response"
    CAPACITY_PLANNING = "capacity-planning"
    PREDICTIVE_SCALING = "predictive-scaling"
    COST_OPTIMIZATION = "cost-optimization"
    ONCALL_COPILOT = "oncall-copilot"
