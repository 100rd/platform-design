# Developer Manifest: Platform Consumer Agreement

This document defines the shared responsibility model, standard practices, and core expectations for application engineering teams consuming our Internal Developer Platform (IDP). It establishes the developer contract necessary to maintain velocity, reliability, and security across all workloads.

---

## 1. The Shared Responsibility Model

To ensure high availability and speed, the boundary between the Platform Team and Application Teams is defined as follows:

```
┌────────────────────────────────────────────────────────┐
│               APPLICATION TEAMS OWN:                   │
│   Workload Code & Dependencies · DB Schema Migrations  │
│  Resource Limits & Budgets · App SLOs & Alerts Config  │
└───────────────────────────┬────────────────────────────┘
                            │ Deployed on top of
┌───────────────────────────▼────────────────────────────┐
│                 THE PLATFORM TEAM OWNS:                │
│   EKS Control Plane & Nodes · Global Network & TGW     │
│  Secrets Vault & IAM Auth · Observability Pipelines    │
└────────────────────────────────────────────────────────┘
```

### The Platform Team Guarantees:
* **The Paved Road (Golden Paths):** Fully managed compute, networking, secrets delivery, and CI/CD pipelines that work out-of-the-box.
* **Cluster Availability:** Maintenance of EKS, CNI, Karpenter, Ingress, and core Kubernetes add-ons.
* **Security Guardrails:** Automated encryption, image verification, network isolation, and identity federation.
* **Continuous Feedback:** Active support, documentation, and tooling updates based on developer user research.

### Application Teams Guarantee:
* **Workload Hygiene:** Proper resource allocation, structured logging, graceful shutdown, and container security.
* **Release Ownership:** Application configuration, database migrations, progressive rollout validation, and alert triage.
* **FinOps Compliance:** Operating within designated namespace budgets and optimizing workload resource usage.

---

## 2. The Golden Rules of Workload Hygiene

Any workload running on the platform must adhere to the following five operational rules:

### Rule 1: GitOps is the Single Source of Truth
* **Standard:** No manual changes (no `kubectl edit`, `kubectl apply`, or direct dashboard modifications) are permitted in staging or production environments.
* **Enforcement:** ArgoCD continuously reconciles the cluster state against the GitOps repository. Any manual change will be automatically overwritten (drift reconciliation). All changes must go through a Git Pull Request.

### Rule 2: Zero Hardcoded Secrets
* **Standard:** Plaintext secrets, tokens, or private keys must never be committed to Git or injected as static environment variables in templates.
* **Enforcement:** All secrets must be stored in **AWS Secrets Manager** and consumed dynamically via the **External Secrets Operator** (`ExternalSecret` CRD).
* **Reference:** [ESO Integration (ADR-0008)](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0008-external-secrets-operator.md).

### Rule 3: Define CPU and Memory Requests & Limits
* **Standard:** Every container in a pod specification must declare explicit CPU and Memory `requests` and `limits`.
* **Rationale:** This is critical for Karpenter ([ADR-0007](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0007-karpenter-over-cluster-autoscaler.md)) to efficiently schedule and consolidate nodes. Containers without resource declarations risk starving neighboring workloads and causing node instability.
* **Guideline:** Set `requests` based on typical usage, and `limits` to handle peak burst (avoid setting limits excessively higher than requests to prevent OOM kills on shared nodes).

### Rule 4: Structured Logging & Context Propagation
* **Standard:** Applications must emit logs to `stdout`/`stderr` in structured **JSON format**. Standardize on standard trace propagation headers (W3C Trace Context) for all cross-service HTTP/gRPC communication.
* **Rationale:** Grafana Alloy and Loki parse JSON logs dynamically to extract tags. Trace context propagation is required for Grafana Tempo to construct distributed traces across services.
* **Health Checks:** Every service must expose a `/api/health` or `/healthz` endpoint returning HTTP 200 when the app is functional.

### Rule 5: Graceful Shutdown (SIGTERM Handling)
* **Standard:** Applications must handle the `SIGTERM` signal, stop accepting new connections, finish outstanding requests within a 30-second grace period, and then exit.
* **Rationale:** In a dynamic environment where Karpenter regularly consolidates nodes, pods are frequently rescheduled. Proper `SIGTERM` handling ensures zero-downtime releases and rescheduling.

---

## 3. The Paved Road Contract

Application teams can choose to operate on or off the platform's standardized "Paved Road" (Golden Path):

| Feature | On the Paved Road | Off the Paved Road |
|---|---|---|
| **Tech Stack** | Pinned runtime versions (NodeJS/Python/Go) | Custom/unsupported runtimes or custom OS |
| **CI/CD** | Reusable GHA workflows & Kargo SLO gates | Custom GitHub Actions or manual shell scripts |
| **Deployments** | Automated canary rollouts via Argo Rollouts | Standard Kubernetes Deployment rolling updates |
| **Support** | 24/7 Platform team support and SLA guarantees | "You build it, you secure it, you run it, you debug it" |
| **Upgrades** | Automated minor/patch base image updates | Manual tracking and updating of security patches |

---

## 4. Cost & Budget Ownership (FinOps)

Application teams own the cost of the resources they consume:

* **Namespace Tagging:** Every namespace must be labeled with `team = <team_name>` and `project = <project_name>`.
* **Budget Tracking:** Teams must review their monthly OpenCost dashboard ([ADR-0027](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0027-kubernetes-cost-opencost-cur.md)).
* **Sandbox Cleaning:** Sandbox environments and temporary resources must be destroyed when not in use. Automated cron jobs will purge untagged or inactive sandbox resources every Friday at 18:00 UTC.
