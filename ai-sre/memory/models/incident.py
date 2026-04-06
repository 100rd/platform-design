"""Incident history models for the knowledge base."""

from datetime import datetime
from typing import Any, Optional
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class IncidentRecord(BaseModel):
    """A recorded incident with root cause and resolution."""

    incident_id: UUID = Field(default_factory=uuid4)
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    title: str
    cluster: str
    namespace: Optional[str] = None
    severity: str = "medium"
    alertnames: list[str] = Field(default_factory=list)
    symptoms: list[str] = Field(default_factory=list)
    root_cause: Optional[str] = None
    root_cause_category: Optional[str] = None
    resolution_steps: list[str] = Field(default_factory=list)
    resolution_source: str = "agent"  # agent | human | automated
    affected_services: list[str] = Field(default_factory=list)
    related_alerts: list[str] = Field(default_factory=list)
    time_to_detect_seconds: Optional[float] = None
    time_to_mitigate_seconds: Optional[float] = None
    time_to_resolve_seconds: Optional[float] = None
    metrics_snapshot: dict[str, Any] = Field(default_factory=dict)
    postmortem_url: Optional[str] = None
    tags: list[str] = Field(default_factory=list)


class IncidentSearchResult(BaseModel):
    """Result of searching for similar incidents."""

    incident_id: UUID
    title: str
    cluster: str
    root_cause: Optional[str]
    resolution_steps: list[str]
    similarity_score: float
    timestamp: datetime
