"""Incident history store backed by ClickHouse."""

import logging
from typing import Any, Optional

import httpx

from .models.incident import IncidentRecord, IncidentSearchResult

logger = logging.getLogger(__name__)

# ClickHouse connection
CH_URL = "http://clickhouse.monitoring.svc.cluster.local:8123"
CH_DATABASE = "ai_sre"


class IncidentStore:
    """Persistent incident history stored in ClickHouse.

    Provides:
    - Write: record new incidents from agent investigations or human input
    - Search: find similar past incidents by symptoms/alertnames
    - Learn: capture resolution patterns when humans resolve incidents
    """

    def __init__(self, clickhouse_url: str = CH_URL) -> None:
        self.ch_url = clickhouse_url

    async def record_incident(self, incident: IncidentRecord) -> str:
        """Store a new incident record in ClickHouse."""
        sql = (
            f"INSERT INTO {CH_DATABASE}.incidents "
            "(incident_id, timestamp, title, cluster, namespace, severity, "
            "alertnames, symptoms, root_cause, root_cause_category, "
            "resolution_steps, resolution_source, affected_services, "
            "time_to_detect_seconds, time_to_mitigate_seconds, "
            "time_to_resolve_seconds, tags) VALUES "
            f"('{incident.incident_id}', now64(3), "
            f"'{self._escape(incident.title)}', "
            f"'{self._escape(incident.cluster)}', "
            f"'{self._escape(incident.namespace or '')}', "
            f"'{incident.severity}', "
            f"{self._array_str(incident.alertnames)}, "
            f"{self._array_str(incident.symptoms)}, "
            f"'{self._escape(incident.root_cause or '')}', "
            f"'{self._escape(incident.root_cause_category or '')}', "
            f"{self._array_str(incident.resolution_steps)}, "
            f"'{incident.resolution_source}', "
            f"{self._array_str(incident.affected_services)}, "
            f"{incident.time_to_detect_seconds or 0}, "
            f"{incident.time_to_mitigate_seconds or 0}, "
            f"{incident.time_to_resolve_seconds or 0}, "
            f"{self._array_str(incident.tags)})"
        )

        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.post(self.ch_url, content=sql)
            resp.raise_for_status()

        logger.info("Recorded incident %s: %s", incident.incident_id, incident.title)
        return str(incident.incident_id)

    async def search_similar(
        self,
        symptoms: list[str],
        cluster: Optional[str] = None,
        limit: int = 5,
    ) -> list[IncidentSearchResult]:
        """Search for incidents with similar symptoms.

        Uses keyword matching against symptoms and alertnames.
        In production, this would use embedding-based semantic search.
        """
        conditions = []
        for symptom in symptoms:
            escaped = self._escape(symptom)
            conditions.append(
                f"(hasAny(symptoms, ['{escaped}']) OR "
                f"position(lower(title), lower('{escaped}')) > 0 OR "
                f"position(lower(root_cause), lower('{escaped}')) > 0)"
            )

        where_clause = " OR ".join(conditions) if conditions else "1=1"
        if cluster:
            where_clause = f"({where_clause}) AND cluster = '{self._escape(cluster)}'"

        sql = (
            f"SELECT incident_id, title, cluster, root_cause, "
            f"resolution_steps, timestamp "
            f"FROM {CH_DATABASE}.incidents "
            f"WHERE {where_clause} "
            f"ORDER BY timestamp DESC LIMIT {limit} FORMAT JSON"
        )

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(self.ch_url, content=sql)
                resp.raise_for_status()
                data = resp.json()

            results = []
            for row in data.get("data", []):
                results.append(IncidentSearchResult(
                    incident_id=row["incident_id"],
                    title=row["title"],
                    cluster=row["cluster"],
                    root_cause=row.get("root_cause"),
                    resolution_steps=row.get("resolution_steps", []),
                    similarity_score=1.0,  # Placeholder — real scoring from embeddings
                    timestamp=row["timestamp"],
                ))
            return results
        except Exception as e:
            logger.error("Failed to search incidents: %s", e)
            return []

    async def capture_resolution(
        self,
        incident_id: str,
        resolution: str,
        resolution_steps: list[str],
        resolved_by: str = "human",
    ) -> None:
        """Update an incident with human-provided resolution.

        This enables auto-learning: agents can reference how
        similar incidents were resolved by humans.
        """
        sql = (
            f"ALTER TABLE {CH_DATABASE}.incidents "
            f"UPDATE resolution_source = '{resolved_by}', "
            f"resolution_steps = {self._array_str(resolution_steps)}, "
            f"root_cause = '{self._escape(resolution)}' "
            f"WHERE incident_id = '{incident_id}'"
        )

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(self.ch_url, content=sql)
                resp.raise_for_status()
            logger.info("Captured resolution for incident %s", incident_id)
        except Exception as e:
            logger.error("Failed to capture resolution: %s", e)

    @staticmethod
    def _escape(value: str) -> str:
        """Escape single quotes for ClickHouse SQL."""
        return value.replace("'", "\\'")

    @staticmethod
    def _array_str(items: list[str]) -> str:
        """Convert Python list to ClickHouse array literal."""
        escaped = [f"'{item.replace(chr(39), chr(92) + chr(39))}'" for item in items]
        return f"[{', '.join(escaped)}]"
