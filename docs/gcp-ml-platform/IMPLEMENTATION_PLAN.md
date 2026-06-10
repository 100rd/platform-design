# GCP ML Platform — Implementation Plan

> **Status:** PLAN (not executed). Planning-only — no `terraform apply` / cluster
> mutation is implied by this document. Execution happens later, per-workstream,
> via `/infra-team` under the project's ADR-first, PR-based, apply-gated workflow.
>
> **Grounding:** state mapped 2026-06-10 from the platform-design `graphify-out/`
> graph + repo scan. This plan targets the GCP ML-platform engineering scope
> (elastic GCP infra + K8s for ML, ML CI/CD, model + ML observability, system
> observability, self-serve enablement, SOC posture + on-call).
>
> **Rev 2 (2026-06-10):** code-grounded review folded in (§10). 8 of 9 suggestions
> applied; one (ADR numbering) rejected as factually wrong — ADR-0035 already exists.

---

## 1. Current state (what already exists)

GPU on GKE in GCP is **already done** and is the foundation this plan builds on.

| Layer | Exists today | Where |
|-------|--------------|-------|
| GCP network | GCP VPC for GPU | `terraform/modules/gcp-gpu-vpc`, `catalog/units/gcp-gpu-vpc` |
| GKE cluster | GKE cluster unit | `catalog/units/gcp-gpu-gke` |
| GKE GPU nodes | GPU node pools **with autoscaling** (`min/max_node_count`, per-zone GPU locality, scale-to-zero `min=0`, `spot`) | `terraform/modules/gcp-gke-gpu-nodepools` |
| GCP env + stack | `gcp-staging` env; deployable stack = vpc + gke + nodepools | `terragrunt/gcp-staging`, `catalog/stacks/gcp-gpu-analysis/terragrunt.stack.hcl` |
| GCP identity | GKE Workload Identity (`workload_metadata_config = GKE_METADATA`) + IAM Conditions | `terraform/modules/gcp-gke-gpu-nodepools`, `docs/architecture/logical-service-labels-spec.md` §3.2 |
| Platform taxonomy | Unified `platform:system` label/tag taxonomy + ABAC + OPA enforcement | ADR-0028, `tests/opa/platform_tags.rego` |
| GPU runtime (mostly EKS) | gpu-operator, DCGM, vLLM, DRA, Volcano, HPA, Kata-CC, GPU VictoriaMetrics | `terraform/modules/gpu-inference-*`, `apps/infra/gpu-operator` |
| System observability | OTel Collector, Prometheus 3.x/Thanos, Grafana, Loki, Tempo, Pyroscope, VictoriaMetrics (GPU/DCGM) | `apps/infra/observability/*`, `docs/observability-architecture.md` |
| On-call / alerting | Alertmanager (19 files), PagerDuty (11 files), runbooks with escalation | `apps/infra/observability/*`, `docs/multi-region/runbooks/*`, `docs/sre-runbook.md` |
| Security posture | Kyverno + VAP, Tetragon, Gatekeeper, GuardDuty, iam-baseline, SCPs, secret-rotation, cosign/syft signing | `terraform/modules/*`, `.github/actions/*` |
| ML design (docs only) | Detailed training-pipeline (Airflow DAGs: `train_domain_adapter` → `eval_adapter_debate` → `mine_templates` → `promote_to_edge`; threshold/**drift**/manual retrain triggers; LLM-as-judge debate gate) and inference (vLLM multi-LoRA, TRT-LLM+Triton FIL edge, LiteLLM gateway) | `docs/transaction-analytics/04-training-pipeline.md`, `03-ml-inference.md` |

## 2. Gap map (job-description scope → status)

| # | Responsibility | Status | Gap to close |
|---|----------------|--------|--------------|
| 1 | **Infra mgmt — elastic GCP + K8s for ML** | 🟡 mostly done | GKE node autoscaling/spot/scale-to-zero exist; missing: GKE **parity** of the EKS GPU stack (gpu-operator/DCGM/DRA/Volcano on GKE), **multi-region** expansion, GCP cost controls |
| 2 | **CI/CD for ML** (train/test/deploy) | 🔴 design-only | No deployed orchestrator (Airflow/Kubeflow), **no model registry**, no train→eval→gate→deploy GH Actions wiring. Reuse existing cosign/syft container signing |
| 3 | **Model monitoring** (drift/accuracy/latency/degradation) | 🔴 gap | No Evidently/whylogs deployed; "drift" in repo = *infra* drift, not *model* drift. Latency/uptime covered by system obs |
| 4 | **Collaboration** (data/ML/backend/frontend) | 🟡 partial | Grafana dashboards exist; golden paths + shared contracts + IDP missing |
| 5 | **ML observability** (system + ML metrics, self-serve) | 🟡 split | System health 🟢 strong; **ML metrics (feature/data drift, prediction accuracy, distribution shift) 🔴 absent**; per-team self-serve monitoring 🟡 partial (dashboards yes, Backstage **deferred** ADR-0034) |
| 6 | **SOC compliance + on-call** | 🟡 partial | On-call (PagerDuty + Alertmanager + runbooks) 🟢; controls exist 🟢 but **no SOC2 control-mapping / evidence-collection / posture report**; GCP-side policy parity thin |

**Headline:** the *infrastructure* is largely there (esp. GPU GKE); the **ML-platform layer (CI/CD orchestration + model registry + ML observability/drift) is the real build**, and a thin **GKE parity + SOC-evidence + self-serve** layer rounds it out.

## 3. Constraints & conventions (apply to every workstream)

- **Plan/validate-only, apply-gated.** No `terraform apply` / Helm install without explicit human go + blast-radius review. `/infra-team` runs in plan mode; apply runs from CI on `main` after merge.
- **ADR-first.** Each workstream opens with an ADR (decision + alternatives) before code — matches the existing `docs/adrs/NNNN-*.md` catalogue. **Next free number is 0036** (0035 = ADR Control Tower + AFT, already merged; 0033 reserved).
- **ADR-0028 platform taxonomy (MANDATORY).** Every new resource (Terraform, Helm, ArgoCD app) must carry `platform:system` / `platform:component` / `platform:owner` labels/tags. IAM policies for S3/KMS/SQS/Secrets include the ABAC condition (`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`); the GCP equivalent uses label-scoped IAM Conditions. OPA `tests/opa/platform_tags.rego` enforces this at plan time.
- **Repo idioms:** Terragrunt **catalog units** (`catalog/units/*`) composed into **stacks** (`catalog/stacks/*`); in-cluster delivery via **ArgoCD apps** (`apps/infra/*`); reusable Terraform modules (`terraform/modules/*`) with a `*.tftest.hcl`.
- **GCP provider** standard, Workload Identity for pod→GCP auth (mirror the AWS Pod-Identity pattern). No secrets in code (Secret Manager + ESO).
- **Reuse, don't reinvent:** container build/sign (cosign/syft composites), observability stack (Prometheus/Grafana/Alertmanager/OTel), CI (terragrunt-plan/apply, two-step rollout).
- **Preserve product fiction** (transaction-analytics domain, edge/UK bare-metal, ai-sre) as design-ahead unless a workstream explicitly implements a slice.

## 4. Workstreams

Each is independently shippable, ADR-gated, and maps to one `/infra-team` run.

### WS-A — GKE ML infrastructure parity & elasticity  *(builds on the done GPU-GKE base)*
- **Objective:** bring the GKE GPU platform to parity with the EKS GPU stack, make it multi-region, and govern cost.
- **Already available (do NOT rebuild — `gcp-gke-gpu-nodepools`):**
  | Capability | Status | Location |
  |------------|--------|----------|
  | Spot/preemptible GPU pools | ✅ done | `spot = optional(bool, false)` |
  | Scale-to-zero | ✅ done | `min_node_count = optional(number, 0)` |
  | Per-zone GPU locality (multi-zone via multiple pools) | ✅ done | `location = var.zone` per pool |
  | Workload Identity on nodes | ✅ done | `workload_metadata_config { mode = "GKE_METADATA" }` |
- **Net-new build:** GKE-targeted equivalents of `gpu-operator` (NVIDIA GPU Operator / GKE GPU drivers), `DCGM` exporter, **DRA / Dynamic Resource Allocation**, batch scheduling (**Volcano** or GKE **Kueue**), HPA/KEDA for serving; **multi-region** expansion (regional GKE in ≥2 regions + cross-region serving failover); **GCP cost controls**.
- **Reuse:** `gcp-gke-gpu-nodepools`, `gcp-gpu-vpc`, `gcp-gpu-analysis` stack.
- **Deliverables:** `terraform/modules/gke-gpu-operator`, `gke-gpu-dcgm`, `gke-gpu-scheduling`; **`terraform/modules/gcp-billing-budget`** (`google_billing_budget`, per-project GPU spend alerts at 80/100/120% → PagerDuty via Alertmanager); catalog units + extend the `gcp-gpu-analysis` stack to multi-region; `*.tftest.hcl` each; all carry ADR-0028 labels.
- **Acceptance:** a GPU pod schedules on an autoscaled GKE pool from `min=0`; DCGM metrics flow to VictoriaMetrics/Prometheus; preemptible pool drains gracefully; **GCP billing budget alert fires when GPU spend exceeds threshold**; resources carry `platform:system` labels.

### WS-B — ML CI/CD pipelines (train → test → deploy) + model registry  *(biggest net-new)*
- **Objective:** turn the documented training pipeline into a running, automated system.
- **Decision (locked, §7):** orchestrator = **self-hosted Airflow/Kubeflow on GKE**; model registry = **MLflow** (PostgreSQL backend + S3 artifact store, both ABAC-enforced).
- **Build:** deploy Airflow/Kubeflow as an ArgoCD app on GKE; implement the design's DAGs (`train_domain_adapter` → `eval_adapter_debate` → `mine_templates` → `promote_to_edge`); MLflow registry + versioning + stage gates; a **GitHub Actions** ML pipeline that runs train→eval→**quality gate**→register→deploy, signing artifacts with the existing cosign/syft composites; promote via the existing two-step rollout (`docs/ci-rollout.md`) + Kargo for env promotion.
- **Deliverables:** `apps/infra/airflow` (or kubeflow) ArgoCD app, `apps/infra/mlflow` + `terraform/modules/ml-artifact-store`, `.github/workflows/ml-pipeline.yml`, ADR. `platform:system = ml-pipeline`, components `airflow`/`mlflow`/`model-registry`.
- **Acceptance:** a commit to a model/adapter triggers train→eval→gate→register→staged deploy with a signed artifact and a rollback path; the ArgoCD app + IAM for ML S3/Secrets carry the ADR-0028 `platform:system` label + ABAC condition; Helm values set `ciliumNetworkPolicy.enabled: true` with matching `platform.system`.

### WS-C — Model & ML observability (drift / accuracy / distribution)  *(central to the role)*
- **Objective:** continuous monitoring of model accuracy + data/concept drift in production — the explicit ML-Observability requirement.
- **Decision (locked, §7):** **Evidently / whylogs** (OSS, Prometheus-native — reuses the existing Grafana/Thanos/Alertmanager stack).
- **Build:** a model-monitoring service (`platform:system = ml-monitoring`, components `evidently`/`drift-exporter`) that computes feature drift, data distribution shift, prediction accuracy/quality, and degradation; export as Prometheus metrics into the **existing** Grafana/Thanos/Alertmanager stack; wire **drift → Alertmanager → PagerDuty**; **retrain-trigger mechanism:** Alertmanager webhook receiver → Airflow REST API `POST /api/v1/dags/{dag_id}/dagRuns` (fires the `train_domain_adapter` DAG); fallback if Airflow not yet up = Alertmanager → K8s Job CRD (exact integration detailed in the WS-C ADR). Track serving latency via existing OTel/Tempo. Multi-tenant isolation: namespace-per-model + `platform:system` label filtering (avoids cross-tenant false positives).
- **Deliverables:** `apps/infra/ml-monitoring` (ArgoCD app), drift/accuracy Grafana dashboards, Alertmanager routes + webhook receiver, ADR.
- **Acceptance:** an injected distribution shift raises a drift metric, fires an alert, and opens a retrain trigger; an accuracy dashboard is live per model/tenant.

### WS-D — System & self-serve observability + team enablement
- **Objective:** let individual teams monitor their own workloads (ML and non-ML) without platform-team tickets.
- **Build:** templated per-team Grafana folders/dashboards + alert rules as code (`platform:system = observability`); a self-serve onboarding path. **Backstage stays deferred** (ADR-0034) — ship the lightweight templated self-serve first; revisit Backstage per §7 criteria.
- **Reuse:** existing Prometheus/Grafana/Loki/Tempo/Pyroscope + Alertmanager.
- **Acceptance:** a new team gets a scoped dashboard + alert namespace from a template PR; non-ML production metrics covered alongside ML.

### WS-E — Security posture & SOC compliance + on-call
- **Objective:** make compliance (SOC2-style) demonstrable and complete the on-call posture on GCP.
- **Build:** GCP-side policy parity (GKE Policy Controller / Gatekeeper, **GCP org-policy constraints**); **cross-cloud workload-identity federation** (GCP WIF ↔ AWS IAM) — note basic per-pod GKE Workload Identity is **already done** in `gcp-gke-gpu-nodepools`, so this targets federation + org policy, not basic WI; **SOC2 control mapping + evidence collection** (which existing controls — Kyverno/Tetragon/GuardDuty/iam-baseline/secret-rotation/audit logging — satisfy which control families) + a posture report; formalize the on-call rotation + escalation (PagerDuty already present) and add ML-incident runbooks.
- **Acceptance:** a control-to-evidence matrix exists; GCP workloads are policy-gated; on-call rotation + ML runbooks documented and tested in a tabletop.

### WS-F — Collaboration / golden paths  *(cross-cutting, light)*
- **Objective:** bridge data / ML / backend / frontend for smooth production operation.
- **Build:** golden-path templates (new model service, new pipeline, new dashboard), shared API/data contracts, a RACI + handoff doc, and the self-serve surfaces from WS-D. Largely process + templates, riding WS-B/C/D artifacts.

## 5. Sequencing

```
Phase 0  ADRs (0036+) for WS-A..E + decisions in §7 resolved
Phase 1  WS-A  GKE ML infra parity + multi-region + cost  ─┐ (infra foundation)
Phase 2  WS-B  ML CI/CD + MLflow registry                  ├─ B and C in parallel
         WS-C  ML observability / drift                    ─┘   once A lands
Phase 3  WS-D  self-serve observability + enablement
         WS-E  SOC posture + on-call
Phase 4  WS-F  golden paths (consumes B/C/D outputs)
```

**Dependency graph:**
```
WS-A ──→ WS-B   (deploys onto parity'd GKE)
WS-A ──→ WS-C   (deploys onto parity'd GKE)
WS-B ←─→ WS-C   (bidirectional: drift → retrain trigger)
WS-B ──→ WS-D   (dashboards consume pipeline metrics)
WS-B ──→ WS-F   (golden paths need pipeline template)
WS-C ──→ WS-D   (drift dashboards feed self-serve)
WS-D ──→ WS-F   (self-serve surfaces feed golden paths)
```
WS-A is the gate for B/C. B and C are mutually reinforcing and parallelizable. D/E/F are independent and can start after their dependencies.

## 6. Execution model

- One **ADR + one `/infra-team` run per workstream**, in plan/validate-only mode.
- Each run: ADR → catalog unit/module + ArgoCD app → `terraform/terragrunt` plan + `*.tftest.hcl` → security gate → **draft PR** with plan output → CI green → human review → merge → **apply gated** behind explicit go.
- No live GCP apply, model deploy, or org-policy change without explicit human approval + blast-radius review.

## 7. Decisions (resolved 2026-06-10)

1. **ML orchestrator → self-hosted Airflow/Kubeflow on GKE.** ✅ LOCKED. Matches the design-doc DAGs (`docs/transaction-analytics/04-*`); portable, no managed lock-in. Delivered as an ArgoCD app on GKE (WS-B).
2. **Model registry → MLflow.** ✅ LOCKED. OSS, portable; backs the train→register→deploy flow (WS-B).
3. **ML monitoring → Evidently / whylogs.** ✅ LOCKED. OSS, Prometheus-native → reuses the existing Grafana/Thanos/Alertmanager stack; drift → Alertmanager → PagerDuty + retrain trigger (WS-C).
4. **GKE mode → Standard.** ✅ LOCKED. Autopilot locks down node-level access (no privileged pods, restricted DaemonSets/drivers/custom schedulers) and would block `gpu-operator`, DCGM, DRA, Volcano, Tetragon, Kata-CC, node-tuning, and fine-grained GPU/preemptible control. The existing `gcp-gke-gpu-nodepools` is already Standard.
6. **Elasticity scope → multi-region GCP.** ✅ LOCKED. WS-A expands to multi-region (multiple GCP regions, regional GKE + multi-zone GPU pools, regional MLflow/artifact + cross-region failover for serving). Larger blast radius → extra ADR + apply-gate care.

### Pending (one call left)

5. **Backstage (WS-D self-serve):** ADR-0034 is **Proposed — Deferred** (needs a dedicated owner; its golden-path template is currently AWS-Pod-Identity-wired). **Recommendation: keep deferred** and ship lightweight self-serve in WS-D first. **Revisit Backstage when all three conditions are met:** (a) the GCP ML platform reaches Phase 3 stable, (b) a dedicated IDP owner is assigned, (c) ≥3 teams actively onboard via golden-path templates from WS-F. *Awaiting confirm.*

## 8. Out of scope / preserve

Edge/UK bare-metal (TRT-LLM/Triton edge path), the transaction-analytics product domain, ai-sre agents, and the AWS/EKS GPU-inference estate stay as-is unless a workstream explicitly ports a slice to GKE. This plan adds the GCP ML-platform layer; it does not migrate the AWS control plane.

## 9. Risk register

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | GPU quota unavailable in target GCP region | WS-A blocks all downstream | Medium | Pre-request quota increase for target GPU types (A100/H100) in ≥2 regions before Phase 1 |
| R2 | Self-hosted Airflow/Kubeflow on GKE instability | WS-B reliability, missed SLAs | Medium | Dedicated node pool + PDB + liveness/readiness probes + Alertmanager route |
| R3 | Evidently lacks multi-tenant drift isolation | WS-C false positives across tenants | Low | Namespace-per-model isolation + `platform:system` label filtering |
| R4 | Multi-region GKE GPU cost spiral | Financial, unbudgeted | High | `gcp-billing-budget` alerts (WS-A) + Spot-first policy + scale-to-zero validation |
| R5 | MLflow single point of failure | WS-B deploy pipeline blocked | Medium | MLflow HA with PostgreSQL backend + S3 artifact store (both ABAC-enforced) |

## 10. Review resolution (2026-06-10)

Disposition of the code-grounded review:

| # | Suggestion | Disposition |
|---|------------|-------------|
| 9.1 | WS-A: spot/scale-to-zero/WI already done | ✅ **Applied** — added "Already available" table to WS-A (verified: `spot`, `min_node_count=0`, `GKE_METADATA` in `gcp-gke-gpu-nodepools`). Note: locality is `location = var.zone` per pool (single-zone/pool; multi-zone via multiple pools), not a `locations` list |
| 9.2 | Integrate ADR-0028 platform taxonomy | ✅ **Applied** — added mandatory ADR-0028 constraint to §3 + per-WS `platform:system` values + ABAC acceptance (verified ADR-0028 + `tests/opa/platform_tags.rego` exist) |
| 9.3 | WS-C drift→retrain mechanism | ✅ **Applied** — Alertmanager webhook → Airflow REST `dagRuns` (K8s Job fallback) in WS-C Build |
| 9.4 | GCP cost controls (no GCP budget module) | ✅ **Applied** — added `gcp-billing-budget` to WS-A deliverables + acceptance (verified: AWS `budgets` exists, no GCP equivalent) |
| 9.5 | Backstage un-defer criteria | ✅ **Applied** — three explicit revisit conditions in §7 #5 |
| 9.6 | ADR numbering should start at 0035 | ❌ **Rejected — factually incorrect.** `docs/adrs/0035-control-tower-and-aft.md` already exists on `main` (merged PR #294). The next free number is **0036**, as the plan already states |
| 9.7 | Add risk register | ✅ **Applied** — new §9 |
| 9.8 | WS-E clarify Workload Identity scope | ✅ **Applied** — WS-E now targets cross-cloud WIF federation + GCP org policy (basic per-pod WI already done) |
| 9.9 | Dependency graph | ✅ **Applied** — added to §5 |
