# ADR-0048: AWS ML CI/CD + MLflow registry + drift wiring on EKS — AWS-native backends (RDS Postgres + S3 + ABAC), folding the cluster-agnostic ML layer from ADR-0037/0038

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no Airflow/MLflow deployment on the
  greenfield EKS ML cluster, no `aws-ml-artifact-store` (S3) module, no RDS MLflow
  backend, no `ml-pipeline.yml` workflow, and no drift monitor wired into the AWS
  observability stack. The **cluster-agnostic ML logic** (the Airflow DAG corpus,
  the MLflow train→eval→gate→register→deploy flow, the Evidently/whylogs drift →
  retrain trigger) is **already decided** in
  [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) (WS-B) and
  [ADR-0038](0038-ml-observability-drift.md) (WS-C); this ADR **folds them in by
  reference** and decides only the **AWS-native backend + identity deltas**.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-B "ML CI/CD + model registry" and WS-C "ML observability /
  drift" of the AWS ML Platform plan (`docs/aws-ml-platform/IMPLEMENTATION_PLAN.md`
  §4); folds [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) + [ADR-0038](0038-ml-observability-drift.md)
  (GCP etalons, cluster-agnostic ML layer); risk-register R2 (Airflow stability),
  R3 (drift multi-tenant isolation), R5 (MLflow SPOF).
- Supersedes: (none)
- Superseded by: (none)

## Context

WS-B (ML CI/CD + registry) and WS-C (ML drift observability) are **cluster-agnostic
by design** — the task brief states "the ML layer is cluster-agnostic — mirror
WS-B/WS-C from the GCP plan." The *ML logic* — Airflow as the orchestrator, the DAG
corpus (`train_domain_adapter` → `eval_adapter_debate` → `mine_templates` →
`promote_to_edge`), MLflow as the registry, the train→eval→**quality-gate**→
register→deploy GitHub Actions flow, cosign/syft signing, Kargo promotion, and the
Evidently/whylogs drift → Alertmanager → retrain-trigger wiring — is **already
decided** in [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) and
[ADR-0038](0038-ml-observability-drift.md). Re-deciding it here would duplicate
those ADRs.

What [ADR-0037](0037-ml-cicd-pipeline-mlflow.md)/[ADR-0038](0038-ml-observability-drift.md)
**bake in GCP specifics** that do **not** port to AWS unchanged:

| Concern | ADR-0037/0038 (GCP) | **This ADR (AWS delta)** |
|---|---|---|
| MLflow artifact store | **GCS bucket** + `ml-artifact-store` module + Workload Identity → GSA | **S3 bucket** + new `aws-ml-artifact-store` module + **Pod Identity + ABAC** |
| MLflow backend DB | **Cloud SQL PostgreSQL 16** (out-of-band) | **RDS PostgreSQL** (out-of-band, DBA-owned) |
| Pod → cloud identity | **GKE Workload Identity** (ServiceAccount → GSA) | **EKS Pod Identity** ([ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md)) + ABAC condition |
| Drift/metrics backend | GCP-region Prometheus/Thanos/VictoriaMetrics | same stack on EKS (ADR-0026) — no change |
| Retrain trigger | Alertmanager webhook → Airflow REST `dagRuns` (K8s Job fallback) | **identical** (Airflow REST is cluster-agnostic) — no change |
| Container registry | (GCP) | **ECR** + the existing **ECR pull-through cache** ([ADR-0029](0029-ecr-pull-through-cache.md)) |
| Secret delivery | Secret Manager + ESO | **AWS Secrets Manager + ESO** ([ADR-0008](0008-external-secrets-operator.md)) + rotation ([ADR-0031](0031-secret-rotation.md)) |

So this ADR is deliberately **thin**: it **adopts the WS-B/WS-C ML decisions by
reference** (Airflow + MLflow + Evidently + the GitHub Actions topology + the
retrain wiring — all unchanged) and **decides only the AWS-native backend and
identity substitutions**, plus the greenfield landing on the `aws-eks-gpu-*` cluster
(ADR-0044) under the Volcano scheduler (ADR-0044 D3).

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
mandatory: `platform:system = ml-pipeline` (components `airflow`/`mlflow`/
`model-registry`) for WS-B, `platform:system = ml-monitoring` (components
`evidently`/`drift-exporter`) for WS-C — the same `$system` values ADR-0037/0038 use,
so the AWS ML layer joins the same single-pane dashboards.

## Decision

**Adopt the cluster-agnostic ML layer from [ADR-0037](0037-ml-cicd-pipeline-mlflow.md)
(WS-B) and [ADR-0038](0038-ml-observability-drift.md) (WS-C) unchanged, and substitute
AWS-native backends + identity.** Six plan/validate-only sub-decisions; everything not
listed is inherited from ADR-0037/0038.

### D1 — Orchestrator + DAGs + registry tool: inherit ADR-0037 unchanged

**Apache Airflow** (self-hosted, ArgoCD app, `dags.gitSync`) as the orchestrator and
**MLflow** as the registry — **exactly as ADR-0037 D1**. The DAG corpus, the
train→eval→gate→register→deploy GitHub Actions topology
(`.github/workflows/ml-pipeline.yml`), the cosign/syft signing
(`.github/actions/*`), and Kargo promotion ([ADR-0021](0021-kargo-gitops-promotion-layer.md))
are inherited verbatim — they are cluster-agnostic. Airflow task pods run under the
**Volcano scheduler** (`schedulerName: volcano`) on the `aws-eks-gpu-*` GPU pools
(ADR-0044 D3), inheriting gang/DRA scheduling — the AWS analog of ADR-0037 D1's
"KubernetesExecutor under Volcano." Airflow's own control plane runs on a **non-GPU
(Graviton, plan §7) Karpenter pool** (ADR-0046 D3/R2), not on the expensive GPU
nodes.

### D2 — MLflow artifact store: S3 via new `aws-ml-artifact-store` (the GCS→S3 delta)

Configure MLflow's artifact store as an **S3 bucket**
(`s3://mlflow-artifacts-{env}-{account}`), backed by a new **`aws-ml-artifact-store`**
module — the AWS mirror of ADR-0037 D2's `ml-artifact-store` (GCS). The module:

- **S3 bucket** with **bucket-owner-enforced** object ownership (IAM-only; no ACLs) —
  the S3 analog of GCS uniform bucket-level access.
- **EKS Pod Identity + ABAC:** the MLflow tracking-server ServiceAccount maps to an
  IAM role (Pod Identity, [ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md))
  scoped to the bucket with the **ABAC condition**
  (`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`, value
  `ml-pipeline`) — the AWS mirror of ADR-0037 D2's Workload-Identity→GSA binding, and
  the repo's mandatory ABAC pattern.
- **Versioning enabled** (artifact audit chain — ADR-0037 D2 SOC2 requirement);
  **SSE-KMS** at rest; **lifecycle** rules (Standard-IA after 90d, Glacier after
  365d, expire after 730d — the S3 analog of ADR-0037's Nearline/Coldline ladder).
- **ADR-0028 tags** on the bucket + IAM role.

This mirrors the `ml-artifact-store` (GCS) interface field-for-field where it makes
sense (`bucket_name`, `versioning_enabled`, the lifecycle ladder) so the two clouds'
artifact stores stay diff-able (see the `ml-artifact-store/variables.tf` shape).

### D3 — MLflow backend DB: RDS PostgreSQL, out-of-band (the Cloud SQL→RDS delta)

MLflow's backend store (experiments, runs, registered models, metrics, tags) is a
**dedicated RDS PostgreSQL** instance — the AWS mirror of ADR-0037 D3's dedicated
Cloud SQL. Dedicated (not shared) for the same reasons ADR-0037 D3 gives:
high-frequency per-step metric writes (loss curves on multi-GPU jobs) would contend
with latency-sensitive app DBs; `mlflow db upgrade` migrations have cross-service
blast radius; pooling strategies differ. Provisioned **out-of-band by the DBA team**
(module reference in Implementation notes — this ADR does not create the DB). The
connection host/credentials live in **AWS Secrets Manager** and are consumed via an
**ESO ExternalSecret** ([ADR-0008](0008-external-secrets-operator.md)) with rotation
([ADR-0031](0031-secret-rotation.md)).

### D4 — Drift monitor + retrain trigger: inherit ADR-0038, AWS metrics backend

**Evidently / whylogs** drift monitor (`platform:system = ml-monitoring`) — **exactly
as ADR-0038**: computes feature drift, distribution shift, prediction accuracy,
degradation; exports Prometheus metrics into the **existing EKS** Prometheus/Thanos/
Grafana/Alertmanager stack ([ADR-0026](0026-observability-target-architecture.md));
**drift → Alertmanager → PagerDuty**; **retrain trigger** = Alertmanager webhook →
Airflow REST `POST /api/v1/dags/train_domain_adapter/dagRuns` (K8s Job fallback) —
**all cluster-agnostic, inherited verbatim**. Multi-tenant isolation =
namespace-per-model + `platform:system` label filtering (ADR-0038 R3). The only delta
is that the metrics/alert backend is the EKS-side stack (ADR-0026), which is already
the same LGTM/VictoriaMetrics shape — so effectively **no change** beyond the cluster
it runs on.

### D5 — Container registry: ECR + pull-through cache (the AWS-native registry delta)

ML pipeline images (training, eval, drift-monitor, Airflow custom) are stored in
**ECR**, pulled through the existing **ECR pull-through cache**
([ADR-0029](0029-ecr-pull-through-cache.md)) for upstream bases (NVIDIA NGC, Python).
Images are **signed with cosign + SBOM'd with syft** (the existing
`.github/actions/*` composites, inherited from ADR-0037 D4) and admission-verified —
the AWS-native registry leg that ADR-0037 leaves cloud-generic.

### D6 — Reaffirm scope guards (locked)

- **Fold, don't duplicate.** This ADR **does not re-decide** Airflow-vs-Kubeflow,
  MLflow-vs-alternatives, Evidently-vs-alternatives, the DAG corpus, the GitHub
  Actions topology, the quality-gate thresholds, or the retrain mechanism — those are
  **[ADR-0037](0037-ml-cicd-pipeline-mlflow.md)/[ADR-0038](0038-ml-observability-drift.md)**
  and are inherited. It decides **only** the AWS backend/identity substitutions
  (D2/D3/D5) + the greenfield landing (D1/D4).
- **Greenfield EKS cluster.** WS-B/WS-C land on the `aws-eks-gpu-*` cluster
  (ADR-0044), not the `gpu-inference-*` estate.
- **No secrets in code** — Secrets Manager + ESO + rotation (ADR-0008/0031).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels +
  ABAC** mandatory on every S3 bucket, IAM role, ArgoCD app, and workload here.

A reviewer checks conformance by confirming: (a) Airflow + MLflow deploy as ArgoCD
apps on the EKS ML cluster, Airflow tasks under Volcano (D1); (b) MLflow artifacts on
S3 via `aws-ml-artifact-store` with Pod Identity + ABAC + versioning + SSE-KMS (D2);
(c) MLflow backend is a dedicated RDS Postgres, creds via ESO (D3); (d) the
Evidently drift monitor exports to the EKS Prometheus stack and the retrain webhook
hits Airflow REST (D4); (e) pipeline images are in ECR (pull-through cache) and
cosign-signed (D5); (f) every resource carries ADR-0028 tags + the ABAC condition.

## Alternatives considered

### A1 — A single combined AWS ML ADR re-deriving WS-B + WS-C from scratch
Write one big ADR that re-decides the orchestrator, registry, drift tool, DAGs, and
GitHub Actions topology for AWS independently of ADR-0037/0038.
*Rejected because:* WS-B/WS-C are **cluster-agnostic** (task brief) — the ML logic is
identical across clouds, and re-deciding it would duplicate ADR-0037/0038 and risk
drift between the two clouds' ML stories. The correct mirror is to **fold ADR-0037/0038
by reference** and decide only the AWS deltas (this ADR's D2/D3/D5). (This is the task
brief's explicit "otherwise fold and note" path.)

### A2 — S3 artifact store with static IAM keys in-cluster (skip Pod Identity/ABAC)
Mount static AWS access keys for MLflow's S3 access.
*Rejected because:* it violates the no-secrets-in-cluster policy and the mandatory
ABAC/Pod-Identity pattern ([ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md));
Pod Identity + the ABAC condition is the AWS mirror of ADR-0037 D2's Workload-Identity
binding and is non-negotiable (D2).

### A3 — Reuse an existing app database for the MLflow backend
Point MLflow at a shared RDS instance.
*Rejected for the same reasons as ADR-0037 D3:* metric-write contention, migration
blast radius, divergent pooling. A dedicated RDS Postgres (D3) is the AWS mirror of
the dedicated Cloud SQL.

### A4 — Managed registry/orchestrator (SageMaker Pipelines / Model Registry)
Use SageMaker instead of self-hosted Airflow + MLflow.
*Rejected because:* ADR-0037 D1 already chose self-hosted Airflow + MLflow for
portability and to match the existing Airflow DAG corpus; switching to SageMaker on
AWS only would **break cross-cloud parity** (GKE runs Airflow+MLflow) and re-introduce
the managed lock-in ADR-0037 rejected. Recorded as a revisit trigger if a
SageMaker-integrated tenant requirement emerges (analogous to ADR-0037 D1's Vertex-AI
revisit trigger).

## Consequences

### Positive
- **Zero ML-logic drift across clouds:** the orchestrator, DAGs, registry flow, drift
  detection, and retrain trigger are **identical** to GKE (inherited from
  ADR-0037/0038) — one ML operating model, one set of pipeline runbooks.
- **AWS-native data plane:** S3 + RDS + Pod-Identity/ABAC + ECR are the idiomatic AWS
  backends, wired through the repo's existing ESO/rotation/pull-through-cache estate.
- **Thin, low-risk ADR:** by folding ADR-0037/0038, the only net-new decisions are the
  three backend substitutions — small surface, clear review.
- **SOC2 audit chain preserved:** S3 versioning + KMS + ABAC give the same artifact
  audit trail ADR-0037 D2 requires (feeds the WS-E control-to-evidence matrix).

### Negative
- **Cross-ADR coupling:** this ADR is only complete *with* ADR-0037/0038 — a reader
  must follow the references for the full ML design. Mitigated by the explicit
  "inherit / delta" table in Context.
- **Two artifact-store modules in-repo** (`ml-artifact-store` GCS + `aws-ml-artifact-store`
  S3) — the cost of multi-cloud parity; mitigated by mirroring their interfaces.
- **RDS + S3 + ECR lifecycle** to operate alongside the GCP Cloud SQL + GCS — N×
  backend surface, the inherent cost of running the ML layer on both clouds.

### Risks
- **R2 — Airflow stability (inherited).** *Mitigation:* dedicated non-GPU Graviton
  Karpenter pool (D1/ADR-0046), PDB, liveness/readiness, Alertmanager route — same as
  ADR-0037.
- **R3 — drift multi-tenant isolation (inherited).** *Mitigation:* namespace-per-model
  + `platform:system` filtering (D4/ADR-0038).
- **R5 — MLflow SPOF (inherited).** *Mitigation:* MLflow HA + dedicated RDS Postgres
  (Multi-AZ) + S3 artifact store (D2/D3) — the AWS mirror of ADR-0037 R5's
  Cloud-SQL-backed HA.
- **S3/RDS IAM-ABAC misconfig.** A missing `platform:system` tag breaks the ABAC
  condition → MLflow loses bucket/DB access. *Mitigation:* `tests/opa/platform_tags.rego`
  fails the plan if the tag is absent; ABAC is asserted in the module's `*.tftest.hcl`.

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** S3 bucket, RDS
instance, ArgoCD app, or workflow. Implementation is **apply-gated** and lands as
separate, plan/validate-only PRs per the AWS ML Platform plan (WS-B then WS-C).

**Conventions to match (verified against the repo):** `aws ~> 6.0`, Terraform
`~> 1.11`; the `ml-artifact-store` (GCS) module's variable shape is the mirror target
for `aws-ml-artifact-store`; Pod Identity + ABAC per ADR-0018; ESO per ADR-0008; ECR
pull-through per ADR-0029; cosign/syft via `.github/actions/*`. Every resource takes
`tags` (map(string)) with the five ADR-0028 keys.

### Module / app contracts (for the parallel build)

**`aws-ml-artifact-store` (new)** — S3 MLflow artifact store (D2). Mirrors GCS
`ml-artifact-store`.
- Inputs: `bucket_name`, `versioning_enabled` (default `true`),
  `kms_key_arn` (SSE-KMS), `standard_ia_after_days` (default `90`),
  `glacier_after_days` (default `365`), `expire_after_days` (default `730`),
  `mlflow_pod_identity_role_arn` (or create the role), `platform_system`
  (default `ml-pipeline` → drives the ABAC tag), `tags`.
- Outputs: `bucket_name`, `bucket_arn`, `mlflow_pod_identity_role_arn`.

**`apps/infra/airflow` (ArgoCD app — inherit ADR-0037 shape)** — Airflow on EKS, DAG
gitSync, KubernetesExecutor under Volcano, control plane on a non-GPU pool.

**`apps/infra/mlflow` (ArgoCD app)** — MLflow tracking server, S3 artifact store (D2),
RDS backend (D3, creds via ESO).

**`apps/infra/ml-monitoring` (ArgoCD app — inherit ADR-0038 shape)** — Evidently/whylogs
drift monitor, Prometheus export, Alertmanager routes + retrain webhook to Airflow REST.

**`.github/workflows/ml-pipeline.yml` (inherit ADR-0037 D4)** — train→eval→quality-gate
→register→deploy, cosign/syft, ECR push (D5), Kargo promotion.

**Out-of-band (DBA-owned):** the dedicated RDS PostgreSQL for MLflow (D3) — referenced,
not created here.

**Multi-region (ADR-0044 D5):** MLflow + artifact store are regional; the drift monitor
runs per region; the retrain trigger targets the region's Airflow. Pin every
chart/module/action ref (`?ref=vX.Y.Z`).

- Effort: **M** (one new S3 module + four ArgoCD apps inheriting ADR-0037/0038 shapes +
  RDS/ECR/ESO wiring; the ML logic is inherited, not rebuilt).
- Rollback: each app/module independently revertible; the GCP ML stack and the existing
  AWS estates remain authoritative.

## Revisit trigger

Re-open this decision if any of the following hold:
- **ADR-0037 or ADR-0038 changes its core ML decision** (orchestrator, registry, drift
  tool) — re-fold the new decision here; the AWS deltas (D2/D3/D5) likely still hold.
- **A SageMaker-integrated tenant requirement emerges** — re-evaluate A4 (managed
  orchestrator/registry on AWS), accepting the cross-cloud-parity cost.
- **EKS Pod Identity / ABAC model changes** — revisit D2/D3 identity wiring.
- **The greenfield-vs-consolidation call is reversed** (ADR-0044 D6) — the ML layer may
  re-target the `gpu-inference-*` cluster.

## References

- ADR-0037 (the cluster-agnostic ML CI/CD decision being folded):
  in-repo `docs/adrs/0037-ml-cicd-pipeline-mlflow.md`.
- ADR-0038 (the cluster-agnostic drift decision being folded):
  in-repo `docs/adrs/0038-ml-observability-drift.md`.
- MLflow on AWS (S3 artifact store + RDS backend):
  <https://mlflow.org/docs/latest/tracking.html#amazon-s3-and-s3-compatible-storage>
- Apache Airflow Helm chart (gitSync, KubernetesExecutor):
  <https://airflow.apache.org/docs/helm-chart/>
- Evidently (drift, Prometheus): <https://docs.evidentlyai.com/>; whylogs:
  <https://github.com/whylabs/whylogs>
- EKS Pod Identity + ABAC:
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html>
- In-repo: `terraform/modules/ml-artifact-store` (GCS — the mirror target),
  `.github/actions/cosign-sign`, `.github/actions/syft-sbom`, `kargo/`.
- Related ADRs: [ADR-0037](0037-ml-cicd-pipeline-mlflow.md) +
  [ADR-0038](0038-ml-observability-drift.md) (folded ML layer);
  [ADR-0044](0044-aws-eks-gpu-ml-foundation-multiregion.md) (the EKS cluster this
  lands on); [ADR-0018](0018-eks-pod-identity-as-default-workload-identity.md) (Pod
  Identity / ABAC); [ADR-0008](0008-external-secrets-operator.md) (ESO);
  [ADR-0031](0031-secret-rotation.md) (rotation); [ADR-0029](0029-ecr-pull-through-cache.md)
  (ECR pull-through); [ADR-0021](0021-kargo-gitops-promotion-layer.md) (Kargo);
  [ADR-0026](0026-observability-target-architecture.md) (metrics stack);
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (taxonomy —
  mandatory).

---
*Doc-verified 2026-06-15 against MLflow-on-AWS (S3 + RDS), Apache Airflow Helm,
Evidently, and AWS EKS Pod Identity documentation. Thin AWS-backend mirror that folds
the cluster-agnostic ML layer from ADR-0037/0038. Planning-only ADR — proposed, not
yet implemented in platform-design. WS-B + WS-C of the AWS ML platform plan;
implementation apply-gated.*
