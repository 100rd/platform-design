"""Cluster topology store — loads static topology and provides lookup."""

import logging
from pathlib import Path
from typing import Optional

import yaml

from .models.topology import (
    ClusterTopology,
    CriticalService,
    PlatformTopology,
    ServiceDependency,
)

logger = logging.getLogger(__name__)


class TopologyStore:
    """Manages cluster topology knowledge.

    Loads static topology from YAML files (Git-managed).
    Can be extended with dynamic topology from K8s API discovery.
    """

    def __init__(self, topology_path: Optional[str] = None) -> None:
        self.topology = PlatformTopology()
        if topology_path:
            self.load_from_file(topology_path)

    def load_from_file(self, path: str) -> None:
        """Load topology from a YAML file."""
        try:
            with open(path) as f:
                data = yaml.safe_load(f)

            clusters = []
            for c in data.get("clusters", {}).values() if isinstance(
                data.get("clusters"), dict
            ) else data.get("clusters", []):
                if isinstance(c, dict):
                    critical = [
                        CriticalService(name=s) if isinstance(s, str)
                        else CriticalService(**s)
                        for s in c.get("critical_services", [])
                    ]
                    clusters.append(ClusterTopology(
                        name=c.get("name", ""),
                        type=c.get("type", "spoke"),
                        region=c.get("region", ""),
                        k8s_version=c.get("k8s_version", ""),
                        critical_services=critical,
                        dependencies=c.get("dependencies", []),
                    ))

            self.topology = PlatformTopology(clusters=clusters)
            logger.info("Loaded topology: %d clusters", len(clusters))

        except Exception as e:
            logger.error("Failed to load topology from %s: %s", path, e)

    def get_cluster(self, name: str) -> Optional[ClusterTopology]:
        """Get topology for a specific cluster."""
        for c in self.topology.clusters:
            if c.name == name:
                return c
        return None

    def get_dependencies(self, cluster_name: str) -> list[str]:
        """Get upstream dependencies for a cluster."""
        cluster = self.get_cluster(cluster_name)
        return cluster.dependencies if cluster else []

    def get_dependents(self, cluster_name: str) -> list[str]:
        """Get clusters that depend on the given cluster."""
        return [
            c.name
            for c in self.topology.clusters
            if cluster_name in c.dependencies
        ]

    def get_critical_services(self, cluster_name: str) -> list[CriticalService]:
        """Get critical services for a cluster."""
        cluster = self.get_cluster(cluster_name)
        return cluster.critical_services if cluster else []

    def get_blast_radius(self, cluster_name: str) -> dict:
        """Calculate blast radius if a cluster goes down.

        Returns affected clusters and their critical services.
        """
        affected = self.get_dependents(cluster_name)
        result = {
            "source_cluster": cluster_name,
            "affected_clusters": [],
        }
        for dep in affected:
            cluster = self.get_cluster(dep)
            if cluster:
                result["affected_clusters"].append({
                    "name": dep,
                    "critical_services": [s.name for s in cluster.critical_services],
                })
        return result
