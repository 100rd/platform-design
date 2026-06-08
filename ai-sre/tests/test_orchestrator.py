import sys
from pathlib import Path
import pytest

# Ensure the root of the project is in PYTHONPATH
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from agents.orchestrator.agent import SREOrchestrator, Blackboard, Advisory, InvestigationContext
from agents.orchestrator.config import AgentRole


@pytest.mark.asyncio
async def test_blackboard_pattern_lifecycle():
    """Verify that multiple specialist agents can collaborate using a shared Blackboard."""
    # Initialize the orchestrator
    orchestrator = SREOrchestrator()

    # Define an incoming alert that triggers both incident response and AWS cloud enrichment
    alert = {
        "alert_id": "alert-abc-123",
        "labels": {
            "alertname": "kube_pod_crash_looping",
            "cluster": "prod-us-east",
            "namespace": "default",
        }
    }

    # Investigate the alert
    context = await orchestrator.investigate(alert)

    # 1. Verify Blackboard contains the initial incident signal
    blackboard = context.blackboard
    assert isinstance(blackboard, Blackboard)
    
    signals = blackboard.get_signals()
    assert len(signals) == 1
    assert signals[0]["type"] == "alert"
    assert signals[0]["alert_name"] == "kube_pod_crash_looping"
    assert signals[0]["cluster"] == "prod-us-east"

    # 2. Verify multiple specialist agents updated the infrastructure subgraph and wrote findings
    # Incident Response Agent (routed from kube_pod_*) and AWS Cloud Agent (from cross-layer enrichment)
    findings = blackboard.get_findings()
    assert len(findings) == 2

    # Check primary agent finding
    primary_finding = findings[0]
    assert primary_finding.agent_role == AgentRole.INCIDENT_RESPONSE.value
    assert "incident-response" in primary_finding.summary
    assert "kube_pod_crash_looping" in primary_finding.root_cause

    # Check enrichment agent finding
    enrichment_finding = findings[1]
    assert enrichment_finding.agent_role == AgentRole.AWS_CLOUD.value
    assert "aws-cloud" in enrichment_finding.summary
    assert "kube_pod_crash_looping" in enrichment_finding.root_cause

    # 3. Verify target infrastructure subgraph contains updates from both layers
    subgraph = blackboard.get_subgraph()
    assert "k8s_resources" in subgraph
    assert "aws_resources" in subgraph

    k8s_nodes = subgraph["k8s_resources"]["nodes"]
    assert len(k8s_nodes) == 2
    assert any(n["id"] == "k8s-pod-kube_pod_crash_looping" for n in k8s_nodes)

    aws_nodes = subgraph["aws_resources"]["nodes"]
    assert len(aws_nodes) == 2
    assert any(n["id"] == "aws-ec2-prod-us-east" for n in aws_nodes)

    # 4. Verify aggregated advisories includes findings and the infrastructure subgraph
    aggregated = await orchestrator.aggregate_advisories(context)
    assert aggregated["status"] == "advisory_ready"
    assert aggregated["alert_id"] == "alert-abc-123"
    assert len(aggregated["advisories"]) == 2
    assert aggregated["infrastructure_subgraph"] == subgraph
    assert aggregated["aws_enrichment"] is True
