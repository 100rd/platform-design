# AI SRE Component Connectivity & Signal Flow

This document details the architectural connectivity of the Platform Brain SRE (PB-SRE) system, the roles of all participating components, and the sequence of signal flows during an incident investigation.

---

## 1. System Architecture Blueprint

Below is the visual blueprint of the multi-agent AI SRE platform, illustrating how the agents communicate with each other, the shared Blackboard, and the Omniscience database.

![AI SRE Architecture Blueprint](diagrams/ai-sre-architecture-diagram.png)

---

## 2. Participating Components

The PB-SRE platform is composed of the following key modules:

1. **Ingestion API & Alerts Router**:
   - Ingests alerts from Prometheus/Alertmanager, CloudWatch, or Slack.
   - Deduplicates incoming notifications and routes them as standard signal payloads.
2. **Central AI SRE Orchestrator (Claude Opus)**:
   - The primary reasoning and task scheduling hub.
   - Coordinates the active investigation loop, delegates diagnostic tasks, and compiles the final incident advisory.
3. **Shared Blackboard Repository (`Blackboard`)**:
   - The central communication canvas.
   - Stores incident alerts, log metrics, the active topology subgraph, and specialist agent findings.
4. **Omniscience (Knowledge Graph & RAG Store)**:
   - Houses the platform dependency mapping (Neo4j), document chunks (Postgres), and vector embeddings (Qdrant).
   - Serves as the primary source of truth for platform topology and diagnostic runbooks.
5. **Specialist SRE Agents (Claude Sonnet)**:
   - **K8s Cluster Agent**: Inspects namespaces, pods, services, PVCs, and pod event logs.
   - **AWS Cloud Agent**: Inspects EC2 status, EBS performance, Transit Gateway Peering, and GuardDuty findings.
   - **Cloudflare Agent**: Inspects edge tunnels, DNS resolutions, and WAF events.
   - **GPU Health Agent**: Inspects DCGM metrics, NVLink health, ECC errors, and XID hardware errors.
   - **GitOps Agent / Drift Detector**: Scans Git configurations (Helm overlays) to detect manual drifts.
6. **GitOps Remediation Engine**:
   - Commits recommended configuration fixes to git and creates Pull Requests for human SRE reviews.

---

## 3. Signal Flow Sequence

The sequence below illustrates the chronological propagation of signals when a critical alert triggers:

```mermaid
sequenceDiagram
    autonumber
    participant AM as Ingestion (Alertmanager)
    participant OR as Orchestrator
    participant BB as Shared Blackboard
    participant OM as Omniscience (Graph DB)
    participant CF as Cloudflare Agent
    participant K8s as K8s Agent
    participant AWS as AWS Cloud Agent
    participant GO as GitOps Drift/Remediation

    AM->>OR: 1. Send critical Alert Signal (HTTP 504 on API Gateway)
    OR->>BB: 2. Initialize Blackboard & write Alert Signal
    OR->>OM: 3. Query topology subgraph for affected resource (API Gateway)
    OM-->>OR: 4. Return Dependency Subgraph (Cloudflare Tunnel -> AWS ALB -> Pod -> PVC -> EBS)
    OR->>BB: 5. Write Topology Subgraph to Blackboard
    
    par Parallel Investigation
        OR->>CF: 6a. Invoke CF Agent
        CF->>BB: 6b. Read Signals & Subgraph from Blackboard
        CF->>BB: 6c. Check edge tunnels & write CF status (CNAME & Tunnels healthy)
    and
        OR->>K8s: 7a. Invoke K8s Agent
        K8s->>BB: 7b. Read Signals & Subgraph from Blackboard
        K8s->>BB: 7c. Check pod logs/events & write K8s status (Pods Evicted / OOMKilled)
    and
        OR->>AWS: 8a. Invoke AWS Cloud Agent
        AWS->>BB: 8b. Read Signals & Subgraph from Blackboard
        AWS->>BB: 8c. Check EC2/EBS metrics & write AWS status (Memory >98% / Quota alert)
    end

    OR->>BB: 9. Read aggregated findings & subgraphs from Blackboard
    OR->>GO: 10. Query for configuration drifts & remediation options
    GO-->>OR: 11. Return findings (Memory config drift detected, remediation branch prepared)
    OR->>OR: 12. Synthesize final Root Cause Hypothesis (Claude Opus)
    OR->>GO: 13. Trigger PR Creation (Remediation PR opened in GitOps repo)
    OR->>AM: 14. Post Incident Advisory to Slack (Summary, Root Cause, Action PR link)
```
