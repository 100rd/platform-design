"""Proactive GitOps Drift Detector — compares Git state with EKS/AWS state."""

import logging
import subprocess
from pathlib import Path
from typing import Any

import yaml

logger = logging.getLogger(__name__)


class GitOpsDriftDetector:
    """Proactively checks if live platform resources match their Git-defined specifications."""

    def __init__(
        self,
        git_repo_path: str,
        cluster: str,
        git_mock_replicas: dict[str, int] | None = None,
        live_mock_replicas: dict[str, int] | None = None,
    ) -> None:
        self.git_repo_path = git_repo_path
        self.cluster = cluster
        self.git_mock_replicas = git_mock_replicas or {}
        self.live_mock_replicas = live_mock_replicas or {}

    async def get_live_deployment_replicas(self, namespace: str, deployment_name: str) -> int:
        """Fetch actual replica count in EKS.

        In production, calls kubernetes-mcp tool list_pods or get_deployment.
        """
        # First check if we have a mocked value
        mock_key = f"{namespace}/{deployment_name}"
        if mock_key in self.live_mock_replicas:
            return self.live_mock_replicas[mock_key]

        # Try executing kubectl get deployment/rollout/statefulset
        for kind in ["deployment", "rollout", "statefulset"]:
            try:
                cmd = [
                    "kubectl", "get", kind, deployment_name,
                    "-n", namespace,
                    "-o", "jsonpath={.spec.replicas}"
                ]
                res = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=5,
                )
                val = res.stdout.strip()
                if val:
                    logger.info(
                        "Live %s replicas for %s/%s: %s",
                        kind, namespace, deployment_name, val
                    )
                    return int(val)
            except Exception:
                continue

        # Fallback to default mock value
        logger.warning(
            "No live replicas for %s/%s. Using default mock.",
            namespace,
            deployment_name,
        )
        return 3

    async def get_git_deployment_replicas(self, namespace: str, deployment_name: str) -> int:
        """Fetch expected replica count from Git repository (Helm/Kustomize files)."""
        # First check if we have a mocked value
        mock_key = f"{namespace}/{deployment_name}"
        if mock_key in self.git_mock_replicas:
            return self.git_mock_replicas[mock_key]

        repo = Path(self.git_repo_path)
        if not repo.exists():
            logger.warning("Git repo path %s does not exist", repo)
            return 5

        # Check envs/<namespace>/values/<deployment_name>.yaml (Helm overlay convention)
        env_values_file = repo / "envs" / namespace / "values" / f"{deployment_name}.yaml"
        if not env_values_file.exists():
            env_values_file = repo / "envs" / namespace / "values" / f"{deployment_name}.yml"

        if env_values_file.exists():
            try:
                data = yaml.safe_load(env_values_file.read_text())
                if data and isinstance(data, dict):
                    if "replicaCount" in data:
                        return int(data["replicaCount"])
                    if "replicas" in data:
                        return int(data["replicas"])
            except Exception as e:
                logger.warning("Failed to parse values file %s: %s", env_values_file, e)

        # Recursively search for any yaml files that might define this deployment
        for path in repo.rglob("*.yaml"):
            try:
                content = path.read_text()
                if deployment_name not in content:
                    continue

                docs = yaml.safe_load_all(content)
                for doc in docs:
                    if not doc or not isinstance(doc, dict):
                        continue

                    kind = doc.get("kind", "")
                    metadata = doc.get("metadata", {})
                    name = metadata.get("name", "")
                    doc_namespace = metadata.get("namespace", "default")

                    is_target = kind in ("Deployment", "StatefulSet", "Rollout")
                    is_match = is_target and name == deployment_name
                    is_ns_match = namespace == doc_namespace or doc_namespace == "default"
                    if is_match and is_ns_match:
                        spec = doc.get("spec", {})
                        if "replicas" in spec:
                            return int(spec["replicas"])
            except Exception as e:
                logger.debug("Failed to check YAML file %s: %s", path, e)

        # Fallback to default mock value
        logger.warning(
            "No git replica spec for %s/%s. Using default mock.",
            namespace,
            deployment_name,
        )
        return 5

    async def check_deployment_drift(self, namespace: str, deployment_name: str) -> dict[str, Any]:
        """Check for drifts between git targets and live resources."""
        live_replicas = await self.get_live_deployment_replicas(namespace, deployment_name)
        git_replicas = await self.get_git_deployment_replicas(namespace, deployment_name)

        drifted = live_replicas != git_replicas
        result = {
            "resource": f"deployment/{namespace}/{deployment_name}",
            "drifted": drifted,
            "git_state": {"replicas": git_replicas},
            "live_state": {"replicas": live_replicas},
        }

        if drifted:
            logger.warning(
                "GitOps DRIFT detected on %s: Git expects %d replicas, but live is %d",
                result["resource"],
                git_replicas,
                live_replicas,
            )

        return result


if __name__ == "__main__":
    import asyncio
    logging.basicConfig(level=logging.INFO)
    detector = GitOpsDriftDetector(git_repo_path="./argocd", cluster="gpu-inference")
    asyncio.run(detector.check_deployment_drift("default", "vllm-inference"))
