# AWS ML Platform — Implementation Plan

> **Status: PLAN (not executed). Planning-only — no `terraform apply` is implied.**
> No `terraform apply` / EKS cluster mutation / Helm install / ArgoCD sync is implied
> by this document. Execution happens later, per-workstream, via `/infra-team` under
> the project's ADR-first, PR-based, **apply-gated** workflow (apply runs from CI on
> `main` after merge — never from an agent or a feature branch).
>
> **Greenfield, by user choice.** This is a **fresh AWS EKS GPU ML platform built
> from scratch**, structured to **maximise correspondence with the GCP/GKE design**
> (`docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md`, ADRs 0036–0042). It does **not**
> consolidate or depend on the repo's existing `gpu-inference-*` / `gpu-*` AWS
> modules — those are read for patterns and reused only where already generic
> (`karpenter`, `karpenter-nodepools`, `placement-group`, `budgets`, `waf`).
>
> **Grounding:** state mapped 2026-06-15 from a repo scan of `terraform/modules/`,
> `catalog/`, `docs/adrs/`, and the GCP etalon plan/ADRs. AWS provider `~> 6.0`,
> Terraform `~> 1.11` (verified against `terraform/modules/*/versions.tf`). This repo
> uses **terraform**, not tofu.
>
> **Mirror map (this plan ↔ the GKE etalon):** WS-A↔WS-A (ADR-0044 ← 0036), fabric
> ADR-0045 ← 0042 (fabric half), node-strategy ADR-0046 (AWS-specific, GKE got it
> free from `gcp-gke-gpu-nodepools`), serving ADR-0047 ← 0042 (serving half),
> WS-B/WS-C ADR-0048 folds 0037/0038, WS-D/WS-E/WS-F mirror the GCP WS-D/E/F.

---

## 1. Current state (what already exists)

Unlike the GKE etalon — where GPU-on-GKE was *already assembled* — the AWS side has
**generic GPU building blocks but no assembled ML-grade GPU cluster**. This plan
builds that cluster greenfield.

| Layer | Exists today | Where |
|-------|--------------|-------|
| Node provisioning | Karpenter controller + `NodePool`/`EC2NodeClass` with `spot_percentage`, `consolidation_policy` (`WhenEmptyOrUnderutilized`), `consolidate_after`, `placement_group_name`, `availability_zone` pinning | `terraform/modules/karpenter`, `terraform/modules/karpenter-nodepools` |
| HPC networking | EC2 `cluster`/`spread`/`partition` placement groups | `terraform/modules/placement-group` |
| A GPU EKS estate (video) | A GPU EKS cluster + VPC + Karpenter GPU pools (A10G/T4 video analysis) — **separate estate, not the ML cluster** | `terraform/modules/gpu-eks`, `gpu-vpc`; `catalog/stacks/gpu-analysis` |
| A GPU inference estate | `gpu-inference-eks` cluster + gpu-operator/DCGM/DRA/Volcano/vLLM/Kata-CC — **separate estate, reference only** | `terraform/modules/gpu-inference-*`, `catalog/units/gpu-inference-*` |
| Cost guardrail | `aws_budgets_budget` — ACTUAL (50/80/100% default) + FORECASTED, per-account/per-service, SNS + email | `terraform/modules/budgets` |
| WAF | `aws_wafv2_web_acl` — rate-limit + logging | `terraform/modules/waf` |
| L7 / Gateway estate | Cilium Gateway API (ADR-0009), Envoy Gateway secondary L7 (ADR-0025), VPC Lattice (ADR-0023) | `argocd/`, ADRs 0009/0023/0025 |
| Identity | EKS **Pod Identity** + the **ABAC** condition pattern | ADR-0018 |
| Platform taxonomy | Unified `platform:system` tag/label taxonomy + ABAC + **OPA enforcement** | ADR-0028, `tests/opa/platform_tags.rego` |
| System observability | Prometheus 3.x/Thanos, Grafana, Loki, Tempo, Pyroscope, OTel, Alertmanager → PagerDuty, OpenCost + CUR/Athena | `apps/infra/observability/*`, ADR-0026, ADR-0027 |
| Cross-region failover | Health-checked Route 53 DNS failover controller | `failover-controller/` |
| Supply chain | cosign + syft composites; ECR pull-through cache | `.github/actions/*`, ADR-0029 |
| Secrets | AWS Secrets Manager + ESO + rotation | ADR-0008, ADR-0031 |
| ML layer (decided, GCP-backed) | Airflow + MLflow + Evidently + the train→eval→gate→register→deploy flow + drift→retrain — **cluster-agnostic ML logic** | ADR-0037, ADR-0038 (GCP backends) |

**Headline:** AWS has the *primitives* (Karpenter, placement groups, budgets, WAF,
Pod-Identity/ABAC, observability, failover, supply chain) but **no assembled ML GPU
cluster**. The build is (a) a greenfield `aws-eks-gpu-*` day-2 stack at parity with
GKE, (b) its EFA fabric + node strategy + serving front, and (c) landing the
already-decided ML layer (Airflow/MLflow/drift) on it with AWS-native backends.

## 2. Gap map (job-description scope → status)

| # | Responsibility | Status | Gap to close |
|---|----------------|--------|--------------|
| 1 | **Infra mgmt — elastic AWS + K8s for ML** | 🟡 primitives only | Karpenter spot/scale-to-zero/consolidation + placement groups exist; missing: an **assembled `aws-eks-gpu-*` ML cluster** (GPU Operator/DCGM/DRA/Volcano), the **EFA fabric**, a **node strategy** (Karpenter vs managed node groups), **multi-region** expansion, and GPU **cost wiring** (reuse `budgets`) |
| 2 | **CI/CD for ML** (train/test/deploy) | 🔴 design-only | ML logic decided (ADR-0037) but **GCP-backed**; missing: Airflow/MLflow on EKS with **S3 + RDS + Pod-Identity/ABAC** backends, ECR, `ml-pipeline.yml` |
| 3 | **Model monitoring** (drift/accuracy/latency) | 🔴 gap | Drift decided (ADR-0038) but not deployed on EKS; missing: Evidently/whylogs → EKS Prometheus stack → retrain trigger |
| 4 | **Collaboration** (data/ML/backend/frontend) | 🟡 partial | Grafana dashboards exist; golden paths + shared contracts + IDP missing (Backstage deferred, ADR-0034) |
| 5 | **ML observability** (system + ML metrics, self-serve) | 🟡 split | System health 🟢 strong; **ML metrics 🔴 absent**; per-team self-serve 🟡 partial |
| 6 | **SOC compliance + on-call** | 🟡 partial | On-call (PagerDuty + Alertmanager + runbooks) 🟢; controls exist 🟢 but **no SOC2 control-mapping / evidence / posture report**; AWS-side ML-specific policy thin |

**Headline:** the *primitives* are there; the **assembled ML GPU cluster + its fabric
+ the ML-platform layer (CI/CD + registry + drift) on AWS-native backends** is the
real build, with a thin SOC-evidence + self-serve layer rounding it out — the exact
shape of the GKE plan, re-expressed for AWS.

## 3. Constraints & conventions (apply to every workstream)

- **Plan/validate-only, apply-gated.** No `terraform apply` / Helm install / ArgoCD
  sync without explicit human go + blast-radius review. `/infra-team` runs in plan
  mode; apply runs from CI on `main` after merge. (`never_apply: true` in the infra
  profile.)
- **Verification loop before every PR** (per `.claude/rules/terraform.md`):
  `fmt -recursive -check` → `validate` → `tflint --recursive` → `checkov -d .` →
  `plan`; capture the plan for the Draft PR. Terragrunt units:
  `terragrunt hcl fmt` → `run --all validate` → `run --all plan`.
- **ADR-first.** Each workstream is gated by an ADR. **ADRs 0044–0048** cover this
  plan (0044 foundation, 0045 fabric, 0046 node strategy, 0047 serving, 0048 ML
  layer). **Do not exceed 0048** — 0049+ is baremetal territory.
- **ADR-0028 platform taxonomy (MANDATORY).** Every new resource (Terraform, Helm,
  ArgoCD app) carries `platform:system` / `platform:component` / `platform:owner`
  (+ `platform:env` / `platform:managed-by`) tags/labels. IAM for S3/KMS/Secrets/SQS
  includes the **ABAC condition** (`aws:PrincipalTag/platform:system ==
  aws:ResourceTag/platform:system`). OPA `tests/opa/platform_tags.rego` enforces this
  at plan time (already in CI).
  **Coverage caveat (MEDIUM, surfaced by design review):** `tests/opa/platform_tags.rego`
  enforces the taxonomy on *existing* AWS resource types but has **no rules yet for the
  net-new `aws-eks-gpu-*` / `aws-ml-*` resource types** introduced by this plan, so
  taxonomy enforcement on the new modules is **not** automatic. Extending the rego is a
  named WS-E deliverable (see WS-E + §7 #13) — do not assume the new modules are gated.
- **Repo idioms:** Terragrunt **catalog units** (`catalog/units/*`) composed into
  **stacks** (`catalog/stacks/*`); in-cluster delivery via **ArgoCD apps**
  (`apps/infra/*`); reusable Terraform modules (`terraform/modules/*`) each with a
  `*.tftest.hcl` (impl phase). EKS provider auth via the `aws eks get-token` exec
  pattern (as `catalog/units/gpu-inference-vllm`).
- **AWS provider `~> 6.0`, Terraform `~> 1.11`** — verify before any version-gated
  feature. **terraform, not tofu.** EKS Pod Identity + ABAC for pod→AWS auth
  (ADR-0018). No secrets in code (Secrets Manager + ESO, ADR-0008/0031).
- **Reuse, don't reinvent:** `budgets` (not a new budget module), `waf` (not a new
  WAF module), `placement-group`, `karpenter`/`karpenter-nodepools`, cosign/syft
  composites, the observability stack, the `failover-controller`, ECR pull-through.
- **Greenfield, not consolidation:** the `aws-eks-gpu-*` set is new; the
  `gpu-inference-*` estate stays as-is (plan §7 OPEN DECISION, user-confirmed
  greenfield).
- **Preserve product fiction** (transaction-analytics, edge/UK bare-metal, ai-sre) as
  design-ahead unless a workstream explicitly implements a slice.

## 4. Workstreams

Each is independently shippable, ADR-gated, and maps to one or more `/infra-team`
runs. **Every planned Terraform module is named `terraform/modules/aws-...`, its
catalog unit `catalog/units/...`, and the composing stack
`catalog/stacks/aws-gpu-analysis`** so the impl phase is unambiguous.

### WS-A — EKS GPU infrastructure parity & elasticity  *(the greenfield foundation)*
**ADR:** [0044](../adrs/0044-aws-eks-gpu-ml-foundation-multiregion.md) (foundation),
[0045](../adrs/0045-aws-efa-gpu-fabric-placement-groups.md) (fabric),
[0046](../adrs/0046-eks-node-strategy-karpenter-spot.md) (node strategy).

- **Objective:** stand up a greenfield AWS EKS GPU ML cluster at structural parity
  with the GKE GPU plane (GPU Operator + DCGM + DRA + Volcano), add the EFA
  high-performance fabric, decide the node strategy, make it multi-region, and govern
  cost.
- **Net-new build:**
  - Day-2 ML stack: NVIDIA GPU Operator, DCGM, DRA device classes, Volcano (ADR-0044
    D1–D3).
  - EFA fabric: jumbo frames + cluster placement groups + EFA exposure
    (device-plugin under Karpenter / DRA on managed node groups) (ADR-0045).
  - Node strategy: Karpenter default + managed node groups for reserved EFA-DRA
    training; spot/scale-to-zero/consolidation; Capacity Blocks (ADR-0046).
  - Multi-region: regional EKS in ≥2 AWS regions + cross-region serving failover
    (ADR-0044 D5).
- **Reuse:** `terraform/modules/karpenter`, `karpenter-nodepools`, `placement-group`,
  `budgets` (cost), `failover-controller` (cross-region), the EKS provider exec
  pattern.
- **Deliverables (concrete names):**
  | Kind | Name |
  |---|---|
  | module | `terraform/modules/aws-eks-gpu` (greenfield EKS GPU cluster) |
  | module | `terraform/modules/aws-eks-gpu-vpc` (GPU VPC, MTU 9001, EFA SG) |
  | module | `terraform/modules/aws-eks-gpu-operator` (NVIDIA GPU Operator; DCGM off; driver off on Bottlerocket) |
  | module | `terraform/modules/aws-eks-gpu-dcgm` (DCGM Exporter + auto-taint + alert rules) |
  | module | `terraform/modules/aws-eks-gpu-scheduling` (Volcano + DRA device classes) |
  | module | `terraform/modules/aws-eks-gpu-nodepools` (Karpenter GPU pools; spot/scale-to-zero/consolidation/EFA) |
  | module | `terraform/modules/aws-eks-gpu-managed-nodegroup` (reserved EFA-DRA training, Capacity Blocks) |
  | module | `terraform/modules/aws-eks-efa-fabric` (EFA exposure: `mode = device-plugin\|dra`) |
  | reuse | `terraform/modules/budgets` (80/100/120% + FORECASTED → SNS → Alertmanager), `terraform/modules/placement-group` |
  | units | `catalog/units/aws-eks-gpu`, `aws-eks-gpu-vpc`, `aws-eks-gpu-operator`, `aws-eks-gpu-dcgm`, `aws-eks-gpu-scheduling`, `aws-eks-gpu-nodepools`, `aws-eks-efa-fabric`, `aws-eks-gpu-budget` (wraps `budgets`) |
  | stack | `catalog/stacks/aws-gpu-analysis` (multi-region; mirrors `catalog/stacks/gcp-gpu-analysis`) |
  | tests | one `*.tftest.hcl` per module (impl phase) |
  - All carry ADR-0028 tags: `platform:system = ml-platform`, components
    `gpu-operator`/`gpu-dcgm`/`gpu-scheduling`/`gpu-compute`/`gpu-fabric`.
- **Acceptance:** a GPU pod schedules on a Karpenter pool from scale-to-zero; DCGM
  metrics flow to the metrics stack; a spot serving pool drains gracefully; an NCCL
  all-reduce bandwidth test passes on an EFA pool; `budgets` fires an alert when GPU
  spend exceeds threshold; a second region has its own `aws-gpu-analysis` stack;
  every resource carries `platform:system` tags + the ABAC condition where IAM is
  involved.

### WS-B — ML CI/CD pipelines (train → test → deploy) + model registry  *(biggest net-new ML)*
**ADR:** [0048](../adrs/0048-aws-ml-cicd-registry-drift.md) (AWS backends), folding
[0037](../adrs/0037-ml-cicd-pipeline-mlflow.md) (cluster-agnostic ML logic).

- **Objective:** run the already-decided Airflow + MLflow ML pipeline on the
  greenfield EKS cluster with AWS-native backends.
- **Net-new build:** Airflow + MLflow as ArgoCD apps on EKS (Airflow tasks under
  Volcano, control plane on a non-GPU Graviton Karpenter pool); MLflow artifact store
  on **S3** (Pod-Identity + ABAC + versioning + SSE-KMS); MLflow backend on a
  dedicated **RDS Postgres** (creds via ESO); the `ml-pipeline.yml` GitHub Actions
  flow (train→eval→**quality-gate**→register→deploy) reusing cosign/syft; ECR +
  pull-through cache; Kargo promotion. ML *logic* (DAGs, gate thresholds, topology)
  inherited verbatim from ADR-0037.
- **Reuse:** `.github/actions/cosign-sign` + `syft-sbom`, ECR pull-through (ADR-0029),
  ESO (ADR-0008), Kargo (ADR-0021), the `ml-artifact-store` (GCS) variable shape as
  the mirror.
- **Deliverables (concrete names):**
  | Kind | Name |
  |---|---|
  | module | `terraform/modules/aws-ml-artifact-store` (S3 + Pod-Identity/ABAC + lifecycle) |
  | unit | `catalog/units/aws-ml-artifact-store` |
  | ArgoCD app | `apps/infra/airflow` (inherits ADR-0037 shape) |
  | ArgoCD app | `apps/infra/mlflow` (S3 artifact + RDS backend) |
  | workflow | `.github/workflows/ml-pipeline.yml` |
  | out-of-band | dedicated **RDS PostgreSQL** for MLflow (DBA-owned; referenced) |
  - ADR-0028: `platform:system = ml-pipeline`, components `airflow`/`mlflow`/
    `model-registry`; ABAC on the S3/RDS IAM.
- **Acceptance:** a commit to a model/adapter triggers train→eval→gate→register→
  staged deploy with a signed artifact + rollback path; the ArgoCD app + IAM for ML
  S3/Secrets carry the ADR-0028 `platform:system` label + ABAC condition; Cilium
  NetworkPolicy enabled with matching `platform.system`.

### WS-C — Model & ML observability (drift / accuracy / distribution)  *(central to the role)*
**ADR:** [0048](../adrs/0048-aws-ml-cicd-registry-drift.md) D4, folding
[0038](../adrs/0038-ml-observability-drift.md).

- **Objective:** continuous monitoring of model accuracy + data/concept drift in
  production on EKS.
- **Net-new build:** Evidently/whylogs drift monitor (`platform:system =
  ml-monitoring`) exporting Prometheus metrics into the **existing EKS**
  Prometheus/Thanos/Grafana/Alertmanager stack (ADR-0026); **drift → Alertmanager →
  PagerDuty**; **retrain trigger** = Alertmanager webhook → Airflow REST
  `dagRuns` (K8s Job fallback) — inherited verbatim from ADR-0038. Namespace-per-model
  + `platform:system` filtering for multi-tenant isolation.
- **Reuse:** the entire observability stack (ADR-0026), the retrain mechanism
  (cluster-agnostic), serving latency via OTel/Tempo.
- **Deliverables (concrete names):**
  | Kind | Name |
  |---|---|
  | ArgoCD app | `apps/infra/ml-monitoring` (inherits ADR-0038 shape) |
  | dashboards | drift/accuracy Grafana dashboards (per model/tenant) |
  | alerting | Alertmanager routes + retrain webhook receiver |
- **Acceptance:** an injected distribution shift raises a drift metric, fires an
  alert, and opens a retrain trigger; an accuracy dashboard is live per model/tenant.

### WS-D — System & self-serve observability + team enablement
**ADR:** mirrors [0039](../adrs/0039-self-serve-observability.md) (no new ADR needed —
the self-serve mechanism is cluster-agnostic; reuse the existing
`apps/infra/grafana-self-serve`).

- **Objective:** let teams monitor their own ML and non-ML workloads without
  platform-team tickets.
- **Net-new build:** templated per-team Grafana folders/dashboards + alert-rules-as-
  code (`platform:system = observability`), extended with **ML-platform** team
  examples; a self-serve onboarding path. **Backstage stays deferred** (ADR-0034) —
  ship lightweight templated self-serve first.
- **Reuse:** `apps/infra/grafana-self-serve` (already built for the GCP plan), the
  Prometheus/Grafana/Loki/Tempo/Pyroscope + Alertmanager stack.
- **Deliverables:** an `apps/infra/grafana-self-serve/example-teams/team-ml-platform-aws`
  values + ArgoCD application; a templated PR path.
- **Acceptance:** a new team gets a scoped dashboard + alert namespace from a template
  PR; non-ML production metrics covered alongside ML.

### WS-E — Security posture & SOC compliance + on-call
**ADR:** mirrors [0040](../adrs/0040-soc-posture-and-oncall.md) (AWS side; reuse its
control-to-evidence approach).

- **Objective:** make compliance (SOC2-style) demonstrable for the AWS ML platform
  and complete the ML on-call posture.
- **Net-new build:** AWS-side policy for the ML cluster (**Kyverno/VAP + Gatekeeper**,
  SCP coverage for the GPU account); **cross-cloud WIF** where relevant (GCP↔AWS, the
  inverse of ADR-0040); **SOC2 control mapping + evidence collection** (which existing
  controls — Kyverno/Tetragon/GuardDuty/iam-baseline/secret-rotation/audit logging +
  the new S3-versioning/KMS/ABAC artifact chain — satisfy which control families) + a
  posture report; formalize the ML on-call rotation + escalation (PagerDuty present)
  and add ML-incident runbooks.
- **Reuse:** Kyverno/VAP (ADR-0020), Gatekeeper, GuardDuty, iam-baseline, SCPs,
  secret-rotation (ADR-0031), PagerDuty + Alertmanager + runbooks.
- **Deliverables:** a control-to-evidence matrix doc; ML-incident runbooks; the GPU
  Additionally, **extend `tests/opa/platform_tags.rego`** to cover every net-new
  `aws-eks-gpu-*` / `aws-ml-*` / `aws-eks-efa-fabric` / `aws-eks-inference-gateway`
  resource type (the rego currently has no rules for them) so ADR-0028 tags + the ABAC
  condition are enforced at plan time on the new estate. **Owner: WS-E (security-expert),
  with terraform-engineer providing the resource-type list per module.**
  account's policy coverage; (cross-cloud WIF wiring where relevant).
- **Acceptance:** a control-to-evidence matrix exists; the ML cluster's workloads are
  policy-gated; **`tests/opa/platform_tags.rego` covers the net-new `aws-eks-gpu-*` /
  `aws-ml-*` resource types and fails the plan when an ADR-0028 tag is missing**;
  on-call rotation + ML runbooks documented and tabletop-tested.

### WS-F — Collaboration / golden paths  *(cross-cutting, light)*
**ADR:** mirrors [0041](../adrs/0041-golden-paths-collaboration.md) (reuse the
template approach).

- **Objective:** bridge data / ML / backend / frontend for smooth production
  operation.
- **Net-new build:** golden-path templates (new model service / new pipeline / new
  dashboard) targeting the AWS ML stack, shared API/data contracts, a RACI + handoff
  doc, riding the WS-B/C/D artifacts. Largely process + templates.
- **Reuse:** the WS-D self-serve surfaces, the `templates/golden-paths/` directory.
- **Deliverables:** `templates/golden-paths/aws-ml-*` (new-model-service /
  new-pipeline / new-dashboard) + a RACI/handoff doc.
- **Acceptance:** a new model service / pipeline / dashboard can be stood up from a
  template + contract with a documented RACI.

## 5. Sequencing

```
Phase 0  ADRs 0044–0048 + §7 OPEN DECISIONS resolved (human sign-off)
Phase 1  WS-A  EKS GPU parity + EFA fabric + node strategy + multi-region + cost  ─┐ (foundation)
Phase 2  WS-B  ML CI/CD + MLflow (S3+RDS+ABAC)                                      ├─ B and C in parallel
         WS-C  ML observability / drift                                            ─┘   once A lands
Phase 3  WS-D  self-serve observability + enablement
         WS-E  SOC posture + on-call
Phase 4  WS-F  golden paths (consumes B/C/D outputs)
```

**Dependency graph:**
```
WS-A ──→ WS-B   (deploys onto the greenfield EKS GPU cluster)
WS-A ──→ WS-C   (deploys onto the greenfield EKS GPU cluster)
WS-B ←─→ WS-C   (bidirectional: drift → retrain trigger)
WS-B ──→ WS-D   (dashboards consume pipeline metrics)
WS-B ──→ WS-F   (golden paths need the pipeline template)
WS-C ──→ WS-D   (drift dashboards feed self-serve)
WS-D ──→ WS-F   (self-serve surfaces feed golden paths)

within WS-A:  0044 (foundation) ──→ 0045 (fabric) ──→ 0047 (serving)
              0044 ──→ 0046 (node strategy) ──→ 0045 D2/D3 (EFA exposure gated on provisioner)
```
WS-A is the gate for B/C. Inside WS-A, the node strategy (0046) gates the EFA fabric
exposure (0045 D2/D3), which gates the serving front (0047). B and C are mutually
reinforcing and parallelizable. D/E/F are independent and start after their deps.

## 6. Execution model & global acceptance

- One **ADR + one (or a few) `/infra-team` run(s) per workstream**, in
  plan/validate-only mode.
- Each run: ADR → catalog unit/module + ArgoCD app → `terraform`/`terragrunt` plan +
  `*.tftest.hcl` → security gate → **Draft PR** with plan output → CI green → human
  review → merge → **apply gated** behind explicit go.
- No live AWS apply, model deploy, EFA/Capacity-Block reservation, or policy change
  without explicit human approval + blast-radius review. `run --all` multiplies blast
  radius — scope per stack.
- **Global acceptance (the platform is "done" when):** (a) a GPU pod schedules from
  scale-to-zero on the `aws-eks-gpu-*` cluster with DCGM telemetry and an EFA NCCL
  bandwidth test passing; (b) a model commit drives train→eval→gate→register→deploy
  with a signed artifact + rollback; (c) an injected drift fires an alert and a
  retrain trigger; (d) serving runs behind the inference-extension gateway + AWS WAF;
  (e) a second region has its own stack with failover; (f) `budgets` pages on GPU
  spend with per-`system` CUR/OpenCost attribution; (g) a SOC2 control-to-evidence
  matrix exists; (h) a team can self-serve a dashboard/golden-path; (i) **every**
  resource carries ADR-0028 tags and passes `tests/opa/platform_tags.rego`.

## 7. OPEN DECISIONS (for human sign-off)

These must be resolved (or explicitly deferred) before the relevant workstream's
impl run. Recommendations are given; **all need a human y/n.**

| # | Decision | Options | Recommendation | Owning ADR |
|---|----------|---------|----------------|-----------|
| 1 | **Greenfield vs consolidate** with `gpu-inference-*` | (a) greenfield `aws-eks-gpu-*` (b) extend the inference estate | **(a) greenfield — USER-CONFIRMED** (this plan). Recorded for traceability. | 0044 D6/A1 |
| 2 | **Node strategy** | (a) Karpenter-only (b) managed-node-groups-only (c) **hybrid** | **(c) hybrid:** Karpenter default + managed node groups for reserved EFA-DRA training. Forced by the EFA-DRA × Karpenter constraint. | 0046 |
| 3 | **Batch scheduler** | (a) **Volcano** (b) Kueue (c) Kueue-over-Volcano | **(a) Volcano** (parity with GKE; native gang). Kueue-over-Volcano = recorded revisit trigger. | 0044 D3 |
| 4 | **Serving front** | (a) **Envoy Gateway + Gateway API Inference Extension** (b) ALB + Gateway API (c) VPC Lattice | **(a) Envoy default** (inference-extension is Envoy-native; reuse ADR-0025); **(b) ALB = fallback**; **(c) Lattice = OUT** (no cache-aware routing). | 0047 |
| 5 | **EFA instance families** | p4d (A100) / p5 (H100) / p5en (H200) / p6 (B200); trn for Trainium | **NVIDIA p4d/p5/p5en/p6** per workload; **Trainium OUT** (NVIDIA-only estate). Per-region availability + Capacity Blocks are prerequisites. | 0045 |
| 6 | **Single-region-first vs multi-region day-1** | (a) single-region first, documented path to 2nd (b) multi-region day-1 | **(a) single-region first** to de-risk, with the `aws-gpu-analysis` stack built multi-region-ready (2nd region behind the apply gate). Target topology stays multi-region. | 0044 D5 |
| 7 | **Graviton for non-GPU control workloads** | (a) Graviton (arm64) Karpenter pool for Airflow/MLflow/control (b) x86 | **(a) Graviton** for Airflow/MLflow/drift control planes (cost; keeps them off GPU nodes; R2). GPU pools stay x86 (NVIDIA). | 0046 D3 / 0048 D1 |
| 8 | **WAF on inference front** | reuse `waf` (AWS WAF) vs build new | **reuse `waf`** (AWS WAF WebACL) — the Cloud Armor mirror; no new module. | 0047 D4 |
| 9 | **Cost guardrail** | reuse `budgets` (AWS Budgets) vs build `aws-billing-budget` | **reuse `budgets`** at 80/100/120% + FORECASTED → SNS → Alertmanager; CUR/OpenCost (ADR-0027) for attribution. No new module. | 0044 D4 |
| 10 | **MLflow backends** | S3 + RDS (Pod-Identity/ABAC) vs alternatives | **S3 + dedicated RDS Postgres + Pod-Identity/ABAC** (the GCS/Cloud-SQL mirror); RDS out-of-band (DBA). | 0048 D2/D3 |
| 11 | **Backstage (WS-D self-serve)** | defer vs adopt | **Keep deferred** (ADR-0034); ship lightweight templated self-serve. Revisit when: Phase 3 stable + a dedicated IDP owner + ≥3 teams onboarding via WS-F golden paths. | WS-D / 0034 |
| 12 | **EKS Auto Mode for GPU pools** | yes vs no | **No** for GPU pools (blocks EFA-DRA + hides node controls) — the AWS analog of the GKE Standard lock. Fine for non-GPU control workloads. | 0046 D5 |
| 13 | **OPA taxonomy coverage for the new modules** | extend `platform_tags.rego` vs rely on tag-merge convention only | **Extend the rego** to cover the net-new `aws-eks-gpu-*` / `aws-ml-*` / `aws-eks-efa-fabric` / `aws-eks-inference-gateway` resource types — the policy has **no** rules for them today, so enforcement is not automatic. Owner WS-E (security-expert) + terraform-engineer. | WS-E / ADR-0028 |

## 8. Out of scope / preserve

The existing `gpu-inference-*` AWS estate (its EKS cluster, vLLM topology, Kata-CC,
TGW-connect), the `gpu-analysis` video estate, the transaction-analytics product
domain, edge/UK bare-metal, and ai-sre stay as-is. This plan adds a **greenfield AWS
ML-platform GPU cluster + the ML layer**; it does not migrate or consolidate the
existing estates. Trainium/NeuronLink and TPU are out (NVIDIA-only). Disaggregated
prefill/decode is a deferred follow-up ADR.

## 9. Risk register

| # | Risk | Impact | Likelihood | Mitigation |
|---|------|--------|------------|------------|
| R1 | Multi-region GPU cost spiral | Financial, unbudgeted | High | `budgets` 80/100/120%+FORECASTED (WS-A); Karpenter scale-to-zero + spot serving + consolidation; secondary region scale-to-zero, no hot training mirror; Volcano GPU bin-packing; CUR/OpenCost per-`system` attribution |
| R2 | Self-hosted Airflow/MLflow on EKS instability | WS-B reliability, missed SLAs | Medium | Dedicated non-GPU **Graviton** Karpenter pool + PDB + liveness/readiness + Alertmanager route; MLflow HA + Multi-AZ RDS |
| R3 | Evidently lacks multi-tenant drift isolation | WS-C false positives across tenants | Low | Namespace-per-model + `platform:system` filtering |
| R4 | Per-region GPU quota / Capacity Block unavailability | WS-A blocks; failover assumptions break | Medium | Treat per-region GPU **quota + Capacity Block reservations** as explicit prerequisites; prefer multi-region-available families (p4d/p5); reserve **burst** headroom for failover |
| R5 | MLflow single point of failure | WS-B deploy pipeline blocked | Medium | MLflow HA + dedicated **Multi-AZ RDS Postgres** + S3 artifact store (both ABAC-enforced) |
| R6 | **EFA-DRA × Karpenter mismatch** (AWS-specific) | No / broken GPU fabric | Medium | `aws-eks-efa-fabric` `mode` **derived from** the provisioner (0046); CI asserts `mode = dra` only on managed node groups; NCCL bandwidth test as acceptance gate |
| R7 | Spot eviction mid-NCCL-job | Lost training, wasted GPU-hours | Medium | EFA **training** pools off-spot (on-demand/Capacity Blocks); spot only for serving (PDB + failover) |
| R8 | Inference-extension immaturity under load | Serving latency/regression | Low–Med | Stage behind a canary `InferencePool`; keep `ClusterIP` revertible; WAF rules in count-then-block |

## 10. Notes on parity with the GKE etalon

This plan is a deliberate **section-for-section mirror** of
`docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md`. Structural correspondences:

| GKE etalon | This AWS plan | Note |
|---|---|---|
| WS-A (ADR-0036) GPU Operator/DCGM/DRA/Volcano + `gcp-billing-budget` + multi-region | WS-A (ADR-0044) same + **reuse `budgets`** + multi-region | AWS reuses the native budget; GCP had to build one |
| ADR-0042 fabric half (TCPX/TCPXO/DRANET per family) | ADR-0045 (EFA device-plugin/DRA per provisioner) | split axis differs (family vs provisioner) but the per-X matrix shape is identical |
| (settled by `gcp-gke-gpu-nodepools`) | ADR-0046 node strategy | AWS must *decide* what GKE got for free |
| ADR-0042 serving half (GKE Inference Gateway + Cloud Armor) | ADR-0047 (Gateway API Inference Extension on Envoy + AWS WAF) | same inference-extension standard; data-plane + WAF are AWS-specific |
| WS-B/WS-C (ADR-0037/0038, GCS+CloudSQL+GKE WI) | WS-B/WS-C (ADR-0048 folds them, S3+RDS+Pod-Identity/ABAC) | ML logic identical; backends swapped |
| WS-D/E/F (ADR-0039/0040/0041) | WS-D/E/F (reuse those approaches, AWS-flavoured) | self-serve/SOC/golden-paths are largely cluster-agnostic |

---
*Planning-only. Mirrors the GKE etalon plan for a greenfield AWS EKS GPU ML platform.
ADRs 0044–0048 gate the workstreams. Implementation apply-gated; nothing here is
executed. Doc-grounded 2026-06-15 against the repo + the GCP etalon.*
