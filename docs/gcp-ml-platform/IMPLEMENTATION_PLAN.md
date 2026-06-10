# GCP ML Platform — Implementation Plan

> **Status:** PLAN (not executed). Planning-only — no `terraform apply` / cluster
> mutation is implied by this document. Execution happens later, per-workstream,
> via `/infra-team` under the project's ADR-first, PR-based, apply-gated workflow.
>
> **Grounding:** state mapped 2026-06-10 from the platform-design `graphify-out/`
> graph + repo scan. This plan targets the GCP ML-platform engineering scope
> (elastic GCP infra + K8s for ML, ML CI/CD, model + ML observability, system
> observability, self-serve enablement, SOC posture + on-call).

---

## 1. Current state (what already exists)

GPU on GKE in GCP is **already done** and is the foundation this plan builds on.

| Layer | Exists today | Where |
|-------|--------------|-------|
| GCP network | GCP VPC for GPU | `terraform/modules/gcp-gpu-vpc`, `catalog/units/gcp-gpu-vpc` |
| GKE cluster | GKE cluster unit | `catalog/units/gcp-gpu-gke` |
| GKE GPU nodes | GPU node pools **with autoscaling** (`min/max_node_count`, per-zone GPU locality, scale-to-zero `min=0`) | `terraform/modules/gcp-gke-gpu-nodepools` |
| GCP env + stack | `gcp-staging` env; deployable stack = vpc + gke + nodepools | `terragrunt/gcp-staging`, `catalog/stacks/gcp-gpu-analysis/terragrunt.stack.hcl` |
| GCP identity | GKE Workload Identity + IAM Conditions | `docs/architecture/logical-service-labels-spec.md` §3.2 |
| GPU runtime (mostly EKS) | gpu-operator, DCGM, vLLM, DRA, Volcano, HPA, Kata-CC, GPU VictoriaMetrics | `terraform/modules/gpu-inference-*`, `apps/infra/gpu-operator` |
| System observability | OTel Collector, Prometheus 3.x/Thanos, Grafana, Loki, Tempo, Pyroscope, VictoriaMetrics (GPU/DCGM) | `apps/infra/observability/*`, `docs/observability-architecture.md` |
| On-call / alerting | Alertmanager (19 files), PagerDuty (11 files), runbooks with escalation | `apps/infra/observability/*`, `docs/multi-region/runbooks/*`, `docs/sre-runbook.md` |
| Security posture | Kyverno + VAP, Tetragon, Gatekeeper, GuardDuty, iam-baseline, SCPs, secret-rotation, cosign/syft signing | `terraform/modules/*`, `.github/actions/*` |
| ML design (docs only) | Detailed training-pipeline (Airflow DAGs: `train_domain_adapter` → `eval_adapter_debate` → `mine_templates` → `promote_to_edge`; threshold/**drift**/manual retrain triggers; LLM-as-judge debate gate) and inference (vLLM multi-LoRA, TRT-LLM+Triton FIL edge, LiteLLM gateway) | `docs/transaction-analytics/04-training-pipeline.md`, `03-ml-inference.md` |

## 2. Gap map (job-description scope → status)

| # | Responsibility | Status | Gap to close |
|---|----------------|--------|--------------|
| 1 | **Infra mgmt — elastic GCP + K8s for ML** | 🟡 mostly done | GKE node autoscaling exists; missing: GKE **parity** of the EKS GPU stack (gpu-operator/DCGM/DRA/Volcano/HPA on GKE), preemptible/spot GPU + node auto-provisioning tuning, multi-zone elasticity |
| 2 | **CI/CD for ML** (train/test/deploy) | 🔴 design-only | No deployed orchestrator (Airflow/Vertex AI Pipelines/Kubeflow), **no model registry**, no train→eval→gate→deploy GH Actions wiring. Reuse existing cosign/syft container signing |
| 3 | **Model monitoring** (drift/accuracy/latency/degradation) | 🔴 gap | No Evidently/whylogs/Arize/Vertex Model Monitoring deployed; "drift" in repo = *infra* drift, not *model* drift. Latency/uptime covered by system obs |
| 4 | **Collaboration** (data/ML/backend/frontend) | 🟡 partial | Grafana dashboards exist; golden paths + shared contracts + IDP missing |
| 5 | **ML observability** (system + ML metrics, self-serve) | 🟡 split | System health 🟢 strong; **ML metrics (feature/data drift, prediction accuracy, distribution shift) 🔴 absent**; per-team self-serve monitoring 🟡 partial (dashboards yes, Backstage **deferred** ADR-0034) |
| 6 | **SOC compliance + on-call** | 🟡 partial | On-call (PagerDuty + Alertmanager + runbooks) 🟢; controls exist 🟢 but **no SOC2 control-mapping / evidence-collection / posture report**; GCP-side policy parity thin |

**Headline:** the *infrastructure* is largely there (esp. GPU GKE); the **ML-platform layer (CI/CD orchestration + model registry + ML observability/drift) is the real build**, and a thin **GKE parity + SOC-evidence + self-serve** layer rounds it out.

## 3. Constraints & conventions (apply to every workstream)

- **Plan/validate-only, apply-gated.** No `terraform apply` / Helm install without explicit human go + blast-radius review. `/infra-team` runs in plan mode; apply runs from CI on `main` after merge.
- **ADR-first.** Each workstream opens with an ADR (decision + alternatives) before code — matches the existing `docs/adrs/NNNN-*.md` catalogue (next free number ≥ 0036; 0033 reserved).
- **Repo idioms:** Terragrunt **catalog units** (`catalog/units/*`) composed into **stacks** (`catalog/stacks/*`); in-cluster delivery via **ArgoCD apps** (`apps/infra/*`); reusable Terraform modules (`terraform/modules/*`) with a `*.tftest.hcl`.
- **GCP provider** standard, Workload Identity for pod→GCP auth (mirror the AWS Pod-Identity pattern). No secrets in code (Secret Manager + ESO).
- **Reuse, don't reinvent:** container build/sign (cosign/syft composites), observability stack (Prometheus/Grafana/Alertmanager/OTel), CI (terragrunt-plan/apply, two-step rollout).
- **Preserve product fiction** (transaction-analytics domain, edge/UK bare-metal, ai-sre) as design-ahead unless a workstream explicitly implements a slice.

## 4. Workstreams

Each is independently shippable, ADR-gated, and maps to one `/infra-team` run.

### WS-A — GKE ML infrastructure parity & elasticity  *(builds on the done GPU-GKE base)*
- **Objective:** bring the GKE GPU platform to parity with the EKS GPU stack and make it elastically scale ML workloads.
- **Build:** GKE-targeted equivalents of `gpu-operator` (NVIDIA GPU Operator / GKE GPU drivers), `DCGM` exporter, **DRA / Dynamic Resource Allocation**, batch scheduling (**Volcano** or GKE **Kueue**), HPA/KEDA for serving; node auto-provisioning + **preemptible/Spot GPU** pools + scale-to-zero validation; multi-zone GPU locality.
- **Reuse:** `gcp-gke-gpu-nodepools` (autoscaling already in), `gcp-gpu-vpc`, `gcp-gpu-analysis` stack.
- **Deliverables:** `terraform/modules/gke-gpu-operator`, `gke-gpu-dcgm`, `gke-gpu-scheduling`; catalog units + extend the `gcp-gpu-analysis` stack; `*.tftest.hcl` each.
- **Acceptance:** a GPU pod schedules on an autoscaled GKE pool from `min=0`; DCGM metrics flow to VictoriaMetrics/Prometheus; preemptible pool drains gracefully.

### WS-B — ML CI/CD pipelines (train → test → deploy) + model registry  *(biggest net-new)*
- **Objective:** turn the documented training pipeline into a running, automated system.
- **Decision (see §7):** orchestrator = **Vertex AI Pipelines** (GCP-native, managed) **vs** self-hosted **Airflow/Kubeflow** on GKE (matches the design docs' Airflow DAGs). Model registry = **Vertex AI Model Registry** vs **MLflow**.
- **Build:** deploy the chosen orchestrator (ArgoCD app or Vertex), implement the design's DAGs (`train_domain_adapter` → `eval_adapter_debate` → `mine_templates` → `promote_to_edge`); model registry + versioning + stage gates; a **GitHub Actions** ML pipeline that runs train→eval→**quality gate**→register→deploy, signing artifacts with the existing cosign/syft composites; promote via the existing two-step rollout (`docs/ci-rollout.md`) + Kargo for env promotion.
- **Deliverables:** orchestrator module/app, `model-registry` module, `.github/workflows/ml-pipeline.yml`, ADR.
- **Acceptance:** a commit to a model/adapter triggers train→eval→gate→register→staged deploy with a signed artifact and a rollback path.

### WS-C — Model & ML observability (drift / accuracy / distribution)  *(central to the role)*
- **Objective:** continuous monitoring of model accuracy + data/concept drift in production — the explicit ML-Observability requirement.
- **Decision (see §7):** **Evidently** (OSS, Prometheus-native) and/or **whylogs** vs **Vertex AI Model Monitoring** (managed, GKE/endpoint-native) vs **Arize** (already conceptually referenced in `ai-sre`/`docs/sre-runbook.md`).
- **Build:** a model-monitoring service that computes feature drift, data distribution shift, prediction accuracy/quality, and degradation; export as Prometheus metrics so they land in the **existing** Grafana/Thanos/Alertmanager stack; wire **drift → Alertmanager → PagerDuty** and **drift → retrain trigger** (closes the design's "Drift trigger" Airflow DAG loop from WS-B). Track serving latency via existing OTel/Tempo.
- **Deliverables:** `apps/infra/ml-monitoring` (ArgoCD app), drift/accuracy Grafana dashboards, Alertmanager routes, ADR.
- **Acceptance:** an injected distribution shift raises a drift metric, fires an alert, and (optionally) opens a retrain trigger; an accuracy dashboard is live per model/tenant.

### WS-D — System & self-serve observability + team enablement
- **Objective:** let individual teams monitor their own workloads (ML and non-ML) without platform-team tickets.
- **Build:** templated per-team Grafana folders/dashboards + alert rules as code; a self-serve onboarding path; revisit **Backstage** (ADR-0034, currently deferred) as the catalog/golden-path portal — or a lightweight alternative if Backstage stays deferred.
- **Reuse:** existing Prometheus/Grafana/Loki/Tempo/Pyroscope + Alertmanager.
- **Acceptance:** a new team gets a scoped dashboard + alert namespace from a template PR; non-ML production metrics covered alongside ML.

### WS-E — Security posture & SOC compliance + on-call
- **Objective:** make compliance (SOC2-style) demonstrable and complete the on-call posture on GCP.
- **Build:** GCP-side policy parity (GKE Policy Controller / Gatekeeper, Workload Identity hardening, org policy); **SOC2 control mapping + evidence collection** (which existing controls — Kyverno/Tetragon/GuardDuty/iam-baseline/secret-rotation/audit logging — satisfy which control families) + a posture report; formalize the on-call rotation + escalation (PagerDuty already present) and add ML-incident runbooks.
- **Acceptance:** a control-to-evidence matrix exists; GCP workloads are policy-gated; on-call rotation + ML runbooks documented and tested in a tabletop.

### WS-F — Collaboration / golden paths  *(cross-cutting, light)*
- **Objective:** bridge data / ML / backend / frontend for smooth production operation.
- **Build:** golden-path templates (new model service, new pipeline, new dashboard), shared API/data contracts, a RACI + handoff doc, and the self-serve surfaces from WS-D. Largely process + templates, riding WS-B/C/D artifacts.

## 5. Sequencing

```
Phase 0  ADRs (0036+) for WS-A..E + decisions in §7 resolved
Phase 1  WS-A  GKE ML infra parity & elasticity        ─┐ (infra foundation)
Phase 2  WS-B  ML CI/CD + model registry                ├─ B and C can run in parallel
         WS-C  ML observability / drift                 ─┘   once A lands
Phase 3  WS-D  self-serve observability + enablement
         WS-E  SOC posture + on-call
Phase 4  WS-F  golden paths (consumes B/C/D outputs)
```
WS-A is the gate for B/C (they deploy onto the parity'd GKE). B and C are mutually reinforcing (C's drift signal feeds B's retrain trigger) and parallelizable. D/E/F are independent and can start any time after their dependencies.

## 6. Execution model

- One **ADR + one `/infra-team` run per workstream**, in plan/validate-only mode.
- Each run: ADR → catalog unit/module + ArgoCD app → `terraform/terragrunt` plan + `*.tftest.hcl` → security gate → **draft PR** with plan output → CI green → human review → merge → **apply gated** behind explicit go.
- No live GCP apply, model deploy, or org-policy change without explicit human approval + blast-radius review.

## 7. Decisions (resolved 2026-06-10)

1. **ML orchestrator → self-hosted Airflow/Kubeflow on GKE.** ✅ LOCKED. Matches the design-doc DAGs (`docs/transaction-analytics/04-*`); portable, no managed lock-in. Delivered as an ArgoCD app on GKE (WS-B).
2. **Model registry → MLflow.** ✅ LOCKED. OSS, portable; backs the train→register→deploy flow (WS-B).
3. **ML monitoring → Evidently / whylogs.** ✅ LOCKED. OSS, Prometheus-native → reuses the existing Grafana/Thanos/Alertmanager stack; drift → Alertmanager → PagerDuty + retrain trigger (WS-C).
4. **GKE mode → Standard.** ✅ LOCKED (recommended). Autopilot locks down node-level access (no privileged pods, restricted DaemonSets/drivers/custom schedulers) and would block `gpu-operator`, DCGM, DRA, Volcano, Tetragon, Kata-CC, node-tuning, and fine-grained GPU/preemptible control. The existing `gcp-gke-gpu-nodepools` is already Standard.
6. **Elasticity scope → multi-region GCP.** ✅ LOCKED. WS-A expands to multi-region (multiple GCP regions, regional GKE + multi-zone GPU pools, regional MLflow/artifact + cross-region failover for serving). Larger blast radius → extra ADR + apply-gate care.

### Pending (one call left)

5. **Backstage (WS-D self-serve):** ADR-0034 is **Proposed — Deferred** (needs a dedicated owner; its golden-path template is currently AWS-Pod-Identity-wired). **Recommendation: keep deferred** and ship lightweight self-serve in WS-D first (templated Grafana folders + alert-rules-as-code), revisit Backstage once the GCP ML platform stabilises and an owner exists. *Awaiting confirm.*

## 8. Out of scope / preserve

Edge/UK bare-metal (TRT-LLM/Triton edge path), the transaction-analytics product domain, ai-sre agents, and the AWS/EKS GPU-inference estate stay as-is unless a workstream explicitly ports a slice to GKE. This plan adds the GCP ML-platform layer; it does not migrate the AWS control plane.

---

## 9. Review suggestions (code-grounded, 2026-06-10)

> Grounding: each suggestion verified against the current codebase state.
> Author: platform review session.

### 9.1 WS-A: clarify what's already done vs net-new

The plan says "build preemptible/Spot GPU pools + scale-to-zero" — but **both already exist** in `gcp-gke-gpu-nodepools`:

```hcl
# terraform/modules/gcp-gke-gpu-nodepools/variables.tf
spot               = optional(bool, false)    # line 29
min_node_count     = optional(number, 0)      # line 30 — scale-to-zero
```

**Suggestion:** add an "Already available" subsection to WS-A:

| Capability | Status | Location |
|------------|--------|----------|
| Spot/preemptible GPU pools | ✅ done | `gcp-gke-gpu-nodepools` `spot = true` |
| Scale-to-zero (`min=0`) | ✅ done | `gcp-gke-gpu-nodepools` `min_node_count = 0` |
| Multi-zone GPU locality | ✅ done | `gcp-gke-gpu-nodepools` `locations` per pool |
| Workload Identity | ✅ done | node config in `gcp-gke-gpu-nodepools` |

This narrows WS-A net-new scope to: `gke-gpu-operator`, `gke-gpu-dcgm`, `gke-gpu-scheduling` (Volcano/Kueue port), and **multi-region** expansion.

### 9.2 All workstreams: integrate ADR-0028 platform taxonomy

PR #290 (`feature/docs-evaluation`) implemented the unified `platform:system` label/tag taxonomy (ADR-0028) across GCP, AWS, K8s, ABAC IAM, Cilium, SSO, OPA. **All new ML resources must carry these labels.**

**Suggestion:** add to §3 (Constraints):

> - **ADR-0028 platform taxonomy.** Every new resource (Terraform, Helm, ArgoCD app) must carry `platform:system`, `platform:component`, `platform:owner` labels/tags. IAM policies for S3/KMS/SQS/Secrets must include the ABAC condition (`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`). OPA policy `platform_tags.rego` enforces this at plan time.

**Per-workstream integration:**

| WS | platform:system value | Components |
|----|----------------------|------------|
| WS-B | `ml-pipeline` | `airflow`, `mlflow`, `model-registry` |
| WS-C | `ml-monitoring` | `evidently`, `drift-exporter` |
| WS-D | `observability` | `grafana-self-serve`, `alert-rules` |

**WS-B acceptance criteria addition:**
- ArgoCD Application for orchestrator/registry carries `platform.system` label
- IAM policies for ML S3 buckets / Secrets use ABAC condition
- Helm values include `ciliumNetworkPolicy.enabled: true` with matching `platform.system`

### 9.3 WS-C: specify drift → retrain trigger mechanism

The plan says "drift → Alertmanager → PagerDuty + retrain trigger" but does not specify how the retrain trigger works technically.

**Suggestion:** add to WS-C Build:

> Retrain trigger mechanism: Alertmanager webhook receiver → Airflow REST API `POST /api/v1/dags/{dag_id}/dagRuns` (triggers `train_domain_adapter` DAG from `docs/transaction-analytics/04-training-pipeline.md`). Alternative: Alertmanager → K8s Job CRD (if Airflow is not yet deployed). Specific integration to be detailed in WS-C ADR.

### 9.4 Missing: cost controls for GCP GPU

Multi-region GCP with Spot GPU pools creates significant cost risk. The AWS side has a `budgets` module (`terraform/modules/budgets`) but **nothing equivalent exists for GCP**.

**Suggestion:** add to WS-A deliverables:

> - `terraform/modules/gcp-billing-budget` — `google_billing_budget` resource with per-project GPU spend alerts (threshold: 80%/100%/120% of monthly budget), notification to PagerDuty via Alertmanager.

**Add to WS-A acceptance:**

> - GCP billing budget alerts fire when GPU spend exceeds configured threshold.

### 9.5 Decision #5 (Backstage): add un-defer trigger criteria

The plan recommends "keep deferred" but provides no criteria for when to revisit.

**Suggestion:** replace the Pending section with:

> 5. **Backstage (WS-D self-serve):** ADR-0034 is **Proposed — Deferred**. **Recommendation: keep deferred** and ship lightweight self-serve in WS-D first. **Revisit Backstage when all three conditions are met:** (a) GCP ML platform reaches Phase 3 stable, (b) a dedicated IDP owner is assigned, (c) ≥3 teams actively onboard via golden-path templates from WS-F.

### 9.6 ADR numbering: 0035 exists as a gap

The plan references "ADRs (0036+)" but the last existing ADR is 0034 (`docs/adrs/0034-backstage-idp.md`). ADR-0035 does not exist. Unless 0035 is reserved elsewhere, the sequence should start at 0035.

**Suggestion:** change §5 to "ADRs (0035+)" or explicitly note "0035 reserved for [topic]".

### 9.7 Missing: risk register

No risks are documented. For a multi-region GPU ML platform this is a significant gap.

**Suggestion:** add §8.5 or a new §9:

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | GPU quota unavailable in target GCP region | WS-A blocks all downstream | Medium | Pre-request quota increase for target GPU types (A100/H100) in ≥2 regions |
| R2 | Self-hosted Airflow on GKE instability | WS-B reliability, missed SLAs | Medium | Dedicated node pool + PDB + liveness/readiness probes + Alertmanager route |
| R3 | Evidently lacks multi-tenant drift isolation | WS-C false positives across tenants | Low | Namespace-per-model isolation + `platform:system` label filtering |
| R4 | Multi-region GKE GPU cost spiral | Financial, unbudgeted | High | GCP billing budget alerts (§9.4) + Spot-first policy + scale-to-zero validation |
| R5 | Model registry (MLflow) single point of failure | WS-B deploy pipeline blocked | Medium | MLflow HA with PostgreSQL backend + S3 artifact store (both ABAC-enforced) |

### 9.8 WS-E: clarify Workload Identity scope

WS-E mentions "Workload Identity hardening" but `gcp-gke-gpu-nodepools` **already uses** Workload Identity in node config. Clarify that WS-E targets **cross-cloud federation** (GCP WIF ↔ AWS IAM) and **GCP org-level policy constraints**, not the basic per-pod WI which is already done.

### 9.9 Dependency graph (visual)

The textual sequencing in §5 would benefit from an explicit dependency graph:

```
WS-A ───→ WS-B (deploys onto parity'd GKE)
WS-A ───→ WS-C (deploys onto parity'd GKE)
WS-B ←──→ WS-C (bidirectional: drift → retrain trigger)
WS-B ───→ WS-D (dashboards consume pipeline metrics)
WS-B ───→ WS-F (golden paths need pipeline template)
WS-C ───→ WS-D (drift dashboards feed self-serve)
WS-D ───→ WS-F (self-serve surfaces feed golden paths)
```
