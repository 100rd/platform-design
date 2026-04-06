"""Cluster topology models for the knowledge base."""

from typing import Optional

from pydantic import BaseModel, Field


class ServiceDependency(BaseModel):
    """A dependency between two services."""

    source_service: str
    source_namespace: str
    target_service: str
    target_namespace: str
    target_cluster: Optional[str] = None
    protocol: str = "tcp"
    port: Optional[int] = None
    discovery_method: str = "manual"  # manual | hubble | config


class CriticalService(BaseModel):
    """A critical service in a cluster."""

    name: str
    namespace: str
    replicas: int = 1
    is_stateful: bool = False
    slo_defined: bool = False


class ClusterTopology(BaseModel):
    """Topology definition for a single cluster."""

    name: str
    type: str  # hub | spoke
    region: str
    k8s_version: str = ""
    critical_services: list[CriticalService] = Field(default_factory=list)
    dependencies: list[str] = Field(default_factory=list)
    namespaces: list[str] = Field(default_factory=list)


class PlatformTopology(BaseModel):
    """Full platform topology across all clusters."""

    clusters: list[ClusterTopology] = Field(default_factory=list)
    cross_cluster_dependencies: list[ServiceDependency] = Field(default_factory=list)
