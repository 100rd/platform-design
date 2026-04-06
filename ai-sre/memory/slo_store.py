"""SLO store — loads SLO definitions and calculates error budgets."""

import logging
from typing import Optional

import httpx
import yaml

from .models.slo import ErrorBudgetStatus, ServiceSLO, SLOObjective

logger = logging.getLogger(__name__)

VM_URL = "http://vmselect.monitoring.svc.cluster.local:8481"


class SLOStore:
    """Manages SLO definitions and error budget calculations.

    Loads SLO definitions from YAML. Queries VictoriaMetrics
    for current SLI values and calculates error budget status.
    """

    def __init__(self, slo_path: Optional[str] = None) -> None:
        self.slos: list[ServiceSLO] = []
        if slo_path:
            self.load_from_file(slo_path)

    def load_from_file(self, path: str) -> None:
        """Load SLO definitions from a YAML file."""
        try:
            with open(path) as f:
                data = yaml.safe_load(f)

            for slo_data in data.get("slos", []):
                objectives = [
                    SLOObjective(**obj)
                    for obj in slo_data.get("objectives", [])
                ]
                self.slos.append(ServiceSLO(
                    service=slo_data["service"],
                    cluster=slo_data["cluster"],
                    namespace=slo_data.get("namespace", ""),
                    objectives=objectives,
                    owner_team=slo_data.get("owner_team", ""),
                    escalation_channel=slo_data.get("escalation_channel", ""),
                ))
            logger.info("Loaded %d SLO definitions", len(self.slos))

        except Exception as e:
            logger.error("Failed to load SLOs from %s: %s", path, e)

    def get_slo(self, service: str, cluster: str) -> Optional[ServiceSLO]:
        """Get SLO definition for a service."""
        for slo in self.slos:
            if slo.service == service and slo.cluster == cluster:
                return slo
        return None

    def list_slos(self, cluster: Optional[str] = None) -> list[ServiceSLO]:
        """List all SLO definitions, optionally filtered by cluster."""
        if cluster:
            return [s for s in self.slos if s.cluster == cluster]
        return self.slos

    async def get_error_budget(
        self, service: str, cluster: str
    ) -> list[ErrorBudgetStatus]:
        """Calculate current error budget for a service.

        Queries VictoriaMetrics for the SLI metric values
        and computes remaining error budget.
        """
        slo = self.get_slo(service, cluster)
        if not slo:
            return []

        results = []
        for objective in slo.objectives:
            try:
                current_value = await self._query_sli(objective.metric)
                budget_remaining = self._calculate_budget(
                    target=objective.target,
                    current=current_value,
                )
                results.append(ErrorBudgetStatus(
                    service=service,
                    cluster=cluster,
                    objective_name=objective.name,
                    target=objective.target,
                    current_value=current_value,
                    budget_remaining_percent=budget_remaining,
                    window_days=objective.window_days,
                    is_budget_exhausted=budget_remaining <= 0,
                ))
            except Exception as e:
                logger.warning(
                    "Failed to calculate error budget for %s/%s/%s: %s",
                    service,
                    cluster,
                    objective.name,
                    e,
                )

        return results

    async def _query_sli(self, metric: str) -> float:
        """Query VictoriaMetrics for a current SLI value."""
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    f"{VM_URL}/select/0/prometheus/api/v1/query",
                    params={"query": metric},
                )
                resp.raise_for_status()
                data = resp.json()
                results = data.get("data", {}).get("result", [])
                if results:
                    return float(results[0]["value"][1])
        except Exception as e:
            logger.warning("Failed to query SLI metric: %s", e)
        return 0.0

    @staticmethod
    def _calculate_budget(target: float, current: float) -> float:
        """Calculate remaining error budget as a percentage.

        Error budget = (1 - target/100) as the allowable error rate.
        Remaining = ((1 - target/100) - (1 - current/100)) / (1 - target/100) * 100
        """
        if target >= 100:
            return 0.0 if current < 100 else 100.0

        allowed_error = 1 - target / 100
        actual_error = 1 - current / 100

        if allowed_error <= 0:
            return 0.0

        remaining = ((allowed_error - actual_error) / allowed_error) * 100
        return max(0.0, min(100.0, remaining))
