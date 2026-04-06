"""SLO definition models for the knowledge base."""

from typing import Optional

from pydantic import BaseModel, Field


class SLOObjective(BaseModel):
    """A single SLO objective for a service."""

    name: str
    target: float
    window_days: int = 30
    metric: str
    target_ms: Optional[float] = None
    description: str = ""


class ServiceSLO(BaseModel):
    """SLO definitions for a service."""

    service: str
    cluster: str
    namespace: str = ""
    objectives: list[SLOObjective] = Field(default_factory=list)
    owner_team: str = ""
    escalation_channel: str = ""


class ErrorBudgetStatus(BaseModel):
    """Current error budget status for an SLO."""

    service: str
    cluster: str
    objective_name: str
    target: float
    current_value: float
    budget_remaining_percent: float
    window_days: int = 30
    burn_rate_1h: float = 0.0
    burn_rate_6h: float = 0.0
    is_budget_exhausted: bool = False
