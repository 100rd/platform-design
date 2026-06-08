import subprocess
import sys
from pathlib import Path

import pytest

# Ensure the root of the project is in PYTHONPATH
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agents.ops.drift_detector import GitOpsDriftDetector
from agents.ops.gitops_remediation import GitOpsRemediation


@pytest.mark.asyncio
async def test_drift_detector_with_mocks():
    """Verify GitOpsDriftDetector handles mock states correctly."""
    detector = GitOpsDriftDetector(
        git_repo_path="/tmp/fake-repo",
        cluster="test-cluster",
        git_mock_replicas={"default/my-app": 5},
        live_mock_replicas={"default/my-app": 3},
    )

    # Check drift detection (drifted)
    result = await detector.check_deployment_drift("default", "my-app")
    assert result["drifted"] is True
    assert result["git_state"]["replicas"] == 5
    assert result["live_state"]["replicas"] == 3

    # Check drift detection (no drift)
    detector.live_mock_replicas["default/my-app"] = 5
    result = await detector.check_deployment_drift("default", "my-app")
    assert result["drifted"] is False
    assert result["live_state"]["replicas"] == 5


@pytest.mark.asyncio
async def test_drift_detector_git_yaml_parsing(tmp_path):
    """Verify GitOpsDriftDetector parses Kubernetes manifests and Helm value overlays correctly."""
    # Create a temporary directory structure mimicking the git repo
    repo_path = tmp_path / "argocd"
    repo_path.mkdir()

    # 1. Test Helm values overlay parsing
    envs_path = repo_path / "envs" / "dev" / "values"
    envs_path.mkdir(parents=True)
    html2pdf_values = envs_path / "html2pdf.yaml"
    html2pdf_values.write_text("replicaCount: 2\nimage:\n  tag: v1.0.0")

    # 2. Test Kubernetes manifest parsing
    manifests_path = repo_path / "apps" / "my-service"
    manifests_path.mkdir(parents=True)
    my_service_manifest = manifests_path / "deployment.yaml"
    my_service_manifest.write_text("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-service
  namespace: prod
spec:
  replicas: 4
  template:
    metadata:
      labels:
        app: my-service
""")

    detector = GitOpsDriftDetector(git_repo_path=str(repo_path), cluster="test-cluster")

    # Verify Helm values overlay parsing
    git_replicas = await detector.get_git_deployment_replicas("dev", "html2pdf")
    assert git_replicas == 2

    # Verify Kubernetes manifest parsing
    git_replicas = await detector.get_git_deployment_replicas("prod", "my-service")
    assert git_replicas == 4

    # Verify fallback for unknown deployment
    git_replicas = await detector.get_git_deployment_replicas("prod", "unknown-service")
    assert git_replicas == 5  # default fallback


def test_gitops_remediation_workflow(tmp_path):
    """Verify GitOpsRemediation handles git workflows correctly."""
    # Initialize a temporary git repository
    repo_path = tmp_path / "test-git-repo"
    repo_path.mkdir()

    subprocess.run(["git", "init", "-b", "main"], cwd=repo_path, check=True)
    subprocess.run(
        ["git", "config", "user.name", "SRE Agent"],
        cwd=repo_path,
        check=True,
    )
    subprocess.run(
        ["git", "config", "user.email", "sre-agent@example.com"],
        cwd=repo_path,
        check=True,
    )

    # Create a file in main branch
    target_file = repo_path / "values.yaml"
    target_file.write_text("replicaCount: 1\nimage: app:v1")

    subprocess.run(["git", "add", "values.yaml"], cwd=repo_path, check=True)
    subprocess.run(["git", "commit", "-m", "initial commit"], cwd=repo_path, check=True)

    # Propose change
    remediation = GitOpsRemediation(repo_path=str(repo_path))
    command_str = remediation.propose_change(
        file_path="values.yaml",
        target_content="replicaCount: 1",
        replacement_content="replicaCount: 3",
        branch_name="sre-scale-values",
        commit_message="scale values deployment",
        create_pr=False
    )

    # Verify the return value instructions
    assert "git push origin sre-scale-values" in command_str
    assert "gh pr create" in command_str

    # Verify we returned to the original branch (main)
    res = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    )
    assert res.stdout.strip() == "main"

    # Verify file is unmodified on main branch
    assert target_file.read_text() == "replicaCount: 1\nimage: app:v1"

    # Checkout the proposed branch to verify the modification was committed
    subprocess.run(["git", "checkout", "sre-scale-values"], cwd=repo_path, check=True)
    assert target_file.read_text() == "replicaCount: 3\nimage: app:v1"

    # Verify git log on the branch
    log_res = subprocess.run(
        ["git", "log", "-n", "1", "--format=%s"],
        cwd=repo_path,
        capture_output=True,
        text=True,
        check=True,
    )
    assert log_res.stdout.strip() == "scale values deployment"
