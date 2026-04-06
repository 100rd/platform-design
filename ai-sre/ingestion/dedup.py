"""Alert deduplication — groups related alerts within time windows."""

import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)

# Dedup window in seconds (5 minutes)
DEDUP_WINDOW_SECONDS = 300


@dataclass
class AlertGroup:
    """A group of deduplicated alerts."""

    group_key: str
    alertname: str
    cluster: str
    namespace: Optional[str]
    first_seen: float
    last_seen: float
    count: int = 1
    status: str = "firing"
    investigated: bool = False


class AlertDeduplicator:
    """Groups alerts by alertname + cluster + namespace within a time window.

    Prevents multiple agent investigations for the same alert storm.
    """

    def __init__(self, window_seconds: int = DEDUP_WINDOW_SECONDS) -> None:
        self.window = window_seconds
        self.groups: dict[str, AlertGroup] = {}
        self._cleanup_counter = 0

    def _make_key(
        self, alertname: str, cluster: str, namespace: Optional[str]
    ) -> str:
        """Generate dedup group key."""
        return f"{alertname}:{cluster}:{namespace or '_all_'}"

    def should_investigate(
        self,
        alertname: str,
        cluster: str,
        namespace: Optional[str] = None,
    ) -> tuple[bool, str]:
        """Check if this alert should trigger a new investigation.

        Returns (should_investigate, group_key).
        If the alert belongs to an existing group within the dedup window
        that has already been investigated, returns False.
        """
        now = time.time()
        key = self._make_key(alertname, cluster, namespace)

        # Periodic cleanup
        self._cleanup_counter += 1
        if self._cleanup_counter % 100 == 0:
            self._cleanup_expired(now)

        group = self.groups.get(key)
        if group is None:
            # New alert group
            self.groups[key] = AlertGroup(
                group_key=key,
                alertname=alertname,
                cluster=cluster,
                namespace=namespace,
                first_seen=now,
                last_seen=now,
                count=1,
            )
            return True, key

        # Existing group — check if window expired
        if now - group.first_seen > self.window:
            # Window expired, start new group
            self.groups[key] = AlertGroup(
                group_key=key,
                alertname=alertname,
                cluster=cluster,
                namespace=namespace,
                first_seen=now,
                last_seen=now,
                count=1,
            )
            return True, key

        # Within window — increment count
        group.count += 1
        group.last_seen = now

        if group.investigated:
            logger.info(
                "Dedup: alert '%s' on %s/%s grouped (count=%d, already investigating)",
                alertname,
                cluster,
                namespace,
                group.count,
            )
            return False, key

        return True, key

    def mark_investigated(self, group_key: str) -> None:
        """Mark a group as having an active investigation."""
        group = self.groups.get(group_key)
        if group:
            group.investigated = True
            group.status = "investigating"

    def mark_resolved(self, group_key: str) -> None:
        """Mark a group as resolved."""
        group = self.groups.get(group_key)
        if group:
            group.status = "resolved"

    def get_group_stats(self) -> dict[str, dict]:
        """Get statistics for all active groups."""
        now = time.time()
        stats = {}
        for key, group in self.groups.items():
            if now - group.last_seen < self.window * 2:
                stats[key] = {
                    "alertname": group.alertname,
                    "cluster": group.cluster,
                    "namespace": group.namespace,
                    "count": group.count,
                    "status": group.status,
                    "age_seconds": now - group.first_seen,
                }
        return stats

    def _cleanup_expired(self, now: float) -> None:
        """Remove groups older than 2x the dedup window."""
        expired = [
            key
            for key, group in self.groups.items()
            if now - group.last_seen > self.window * 2
        ]
        for key in expired:
            del self.groups[key]
        if expired:
            logger.debug("Cleaned up %d expired alert groups", len(expired))
