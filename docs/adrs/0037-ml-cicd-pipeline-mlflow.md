# ADR-0037: ML CI/CD pipeline — Airflow orchestrator + MLflow registry + GCS artifact store

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no Airflow/MLflow deployment, no
  `ml-artifact-store` Terraform module, and no `ml-pipeline.yml` workflow exist
  yet in this repo. This ADR gates WS-B.
- Date: 2026-06-10
- Authors: platform-team (devops-engineer)
- Related issues: WS-B "ML CI/CD pipelines (train → test → deploy) + model
  registry" (GCP ML Platform plan §4); risk-register R2 (Airflow instability),
  R5 (MLflow single point of failure).
- Supersedes: (none)
- Superseded by: (none)

## Context

The training-pipeline design (`docs/transaction-analytics/04-training-pipeline.md`)
specifies four Airflow DAGs that are currently **design-only** — no orchestrator
is deployed, no model registry exists, and no GitHub Actions pipeline wires
train→eval→gate→deploy. WS-B closes that gap.

Three sub-decisions require explicit ADR coverage because they directly
affect every subsequent ML workstream (WS-C drift-trigger, WS-D dashboards,
WS-E audit trail):

1. **Orchestrator**: Apache Airflow vs Google Kubeflow Pipelines.
2. **Artifact store**: GCS bucket vs other backends for MLflow.
3. **Pipeline topology**: how the GitHub Actions ML pipeline sequences,
   gates, signs, and promotes model artifacts using the existing platform
   tooling (cosign/syft composites, two-step rollout, Kargo).

### Constraints from the plan

- Orchestrator locked to **self-hosted Airflow or Kubeflow on GKE** (plan §7 D1).
- Registry locked to **MLflow with PostgreSQL backend** (plan §7 D2).
- GCP provider `~> 6.0`, Terraform `~> 1.11` (ADR-0036 / `gcp-billing-budget`
  `versions.tf`).
- ADR-0028 **mandatory** on every resource: `platform:system = ml-pipeline`
  on GCP-plane resources (GCS labels key-style: underscore); `platform.system =
  ml-pipeline` on K8s-plane resources (dotted key-style per ADR-0028 §3).
- Secrets via ESO (`external-secrets.io/v1`, ClusterSecretStore
  `gcp-secrets-manager`) — no static credentials in manifests.
- Reuse existing cosign/syft composite actions
  (`.github/actions/cosign-sign`, `.github/actions/syft-sbom`).
- Promote via existing two-step rollout (`docs/ci-rollout.md`) + Kargo.

### Design-doc DAGs

Four triggered DAGs must be wired end-to-end:

| DAG | Purpose |
|-----|---------|
| `train_domain_adapter` | SFT + LoRA on Qwen 2.5 3B (DeepSpeed ZeRO-3, 8× H100 via Volcano gang job) |
| `eval_adapter_debate` | LLM-as-judge debate gate — loads candidate + incumbent into vLLM, runs on held-out eval set |
| `mine_templates` | Batch template mining over same training window |
| `promote_to_edge` | Merge LoRA → base, quantise fp8, compile TRT-LLM engine, build + sign OCI image, register in Kargo |

Two additional monitoring DAGs are contextually required:
`drift_monitor` (hourly, fires retrain trigger) and
`post_deployment_smoke` (30 min after edge canary).

## Decision

### D1 — Orchestrator: Apache Airflow (not Kubeflow Pipelines)

Deploy **Apache Airflow 2.9** as the ML pipeline orchestrator, self-hosted on GKE
via the [official Apache Airflow Helm chart](https://airflow.apache.org/docs/helm-chart/),
delivered as an **ArgoCD Application** (`apps/infra/airflow/`). DAG code is
stored in `apps/infra/airflow/dags/` and sync'd into Airflow via a **Git sync
sidecar** (the chart's `dags.gitSync` feature pointing at the repo).

**Chosen over Kubeflow Pipelines because:**

- **DAGs already written as Airflow DAGs.** `docs/transaction-analytics/04-training-pipeline.md`
  is expressed entirely as Airflow DAGs with explicit `triggered` schedules,
  inter-DAG dependencies via `TriggerDagRunOperator`, and Airflow-native retrain
  triggers (REST `POST /api/v1/dags/{dag_id}/dagRuns` fired by the WS-C
  drift-monitor Alertmanager webhook). Migrating to Kubeflow Pipeline SDK would
  require rewriting every DAG as a Python component graph — pure scope-growth.
- **Operational parity with the existing design.** The DAG catalogue (table in
  §04-training-pipeline.md) names Airflow constructs. All runbooks and the WS-C
  retrain mechanism (`Alertmanager → Airflow REST API`) reference Airflow. A
  Kubeflow path would force dual-stack or a full rewrite.
- **Lighter resource footprint on GKE.** Airflow scheduler + webserver +
  `KubernetesExecutor` workers run at ~2 GiB steady-state RAM; a full Kubeflow
  installation (Pipelines + Metadata + MinIO + Argo) easily exceeds 8 GiB
  before a single pipeline runs. Given R2 (Airflow instability), adding a
  heavier system raises risk further.
- **GitOps-friendly DAG distribution.** `dags.gitSync` pulls DAGs from the same
  repo — no separate DAG registry. Kubeflow Pipelines requires compiling +
  uploading pipeline YAML out-of-band.
- **KubernetesExecutor gang-scheduling integration.** Each Airflow task pod runs
  under the Volcano scheduler (`schedulerName: volcano`) on the GPU node pool,
  inheriting D2/gang/DRA scheduling from ADR-0036 without any Airflow plugin.

Kubeflow Pipelines' strengths (rich lineage UI, built-in metadata store,
TFX/Vertex SDK) are real but do not outweigh the cost of rewriting the Airflow
DAG corpus. **Revisit D1 if** a second orchestrator requirement emerges that is
structurally incompatible with Airflow (e.g., a Vertex-AI-integrated tenant
pipeline requiring native KFP SDK).

### D2 — MLflow artifact store: GCS bucket (not S3, not local filesystem)

Configure MLflow to use a **GCS bucket** (`gs://mlflow-artifacts-{env}-{project}`)
as its artifact store, backed by the new **`ml-artifact-store` Terraform module**:

- **Uniform bucket-level access** (IAM-only; no per-object ACLs).
- **Workload Identity binding** — MLflow tracking server `ServiceAccount`
  (Kubernetes) bound to a Google Service Account via Workload Identity
  Federation, granting `roles/storage.objectAdmin` on the bucket only.
- **ADR-0028 labels** on the GCS bucket and GSA
  (`platform_system = ml-pipeline`, `platform_component = model-registry`,
  `platform_env`, `platform_owner`, `platform_managed_by`).
- **Object versioning** enabled — preserves deleted/overwritten artifacts for
  the reproducibility audit chain required by §04-training-pipeline.md.
- **Lifecycle rule** — Nearline after 90 days, Coldline after 365 days,
  deletion after 730 days (configurable per env).

**Chosen over S3:** GCS is the natural artifact store for a GKE-hosted MLflow
instance. An S3 artifact store adds a cross-cloud IAM federation dependency or
static AWS credentials in-cluster — violating the Workload-Identity-only policy
for GCP-hosted workloads.

**Chosen over local PersistentVolume:** Local PVC-backed stores are not HA
(pod/node failure loses access), not accessible across multi-region GKE clusters
(ADR-0036 D5), and capacity-constrained for multi-GB TRT-LLM engine artifacts.
GCS is durable, regionally replicated, and already used by `gcp-gke-gpu-nodepools`
via the same Workload Identity mechanism.

### D3 — MLflow backend store: new dedicated Cloud SQL (PostgreSQL 16)

Provision a **new dedicated Cloud SQL PostgreSQL 16** instance for MLflow
(experiments, runs, registered models, metrics, tags). Separated from
application databases because:

- Training runs write high-frequency per-step metric rows (loss curves at
  every log step for an 8× H100 DeepSpeed job). Sharing an instance risks
  IOPS contention with latency-sensitive application databases.
- `mlflow db upgrade` schema migrations on a shared instance have cross-service
  blast radius.
- Connection pooling strategies differ between the MLflow SQLAlchemy client and
  application backends (typically pgbouncer).

The Cloud SQL instance is provisioned out-of-band by the DBA team (module
reference in Implementation notes). The connection host/credentials are written
to GCP Secret Manager and consumed via ESO ExternalSecret.

### D4 — GitHub Actions ML pipeline topology

A single workflow (`.github/workflows/ml-pipeline.yml`) sequences the steps
using the Airflow REST API and MLflow Python client:

```
trigger: push to training/configs/** or training/dags/**
   │
   ├─ validate      yamllint + airflow dags parse (syntax check)
   │
   ├─ train         POST /api/v1/dags/train_domain_adapter/dagRuns
   │                poll dag_run until terminal state
   │
   ├─ eval          POST /api/v1/dags/eval_adapter_debate/dagRuns
   │                poll dag_run until terminal state
   │
   ├─ quality-gate  read eval report from MLflow Run metrics API
   │                fail if win_rate < 0.55 OR p95_distance_regression > 0
   │
   ├─ register      mlflow models create-version + transition to Staging
   │                syft SBOM (.github/actions/syft-sbom)
   │                cosign sign + attest (.github/actions/cosign-sign)
   │
   └─ deploy        POST /api/v1/dags/promote_to_edge/dagRuns
                    Kargo stage-promotion: dev (auto) → staging (reviewer) → prod (manual)
                    two-step rollout per docs/ci-rollout.md
```

The pipeline reuses `.github/actions/syft-sbom` and `.github/actions/cosign-sign`
(keyless, OIDC) for artifact signing — identical to `container-build.yml`.

### D5 — NetworkPolicy: documented follow-up

`values.yaml` files declare `networkPolicy.enabled: true` with `platform.system:
ml-pipeline` selectors. The CiliumNetworkPolicy manifests are a tracked follow-up
in `network-policies/ml-pipeline/` per `network-policies/gpu-inference/00-default-deny.yaml`.
This mirrors ADR-0036's "Network isolation (follow-up)" precedent.

## Alternatives considered

### A1 — Kubeflow Pipelines as the orchestrator
Adopt Kubeflow Pipelines (KFP) SDK v2.
*Rejected because:* DAGs already written and documented as Airflow constructs;
rewriting is pure scope-growth. KFP's heavier footprint (MinIO, Argo Workflows,
KFP UI, metadata store) raises R2 further. WS-C retrain trigger targets Airflow
REST API specifically. See D1 above.

### A2 — Managed Cloud Composer (GCP Airflow-as-a-service)
Use Cloud Composer instead of self-hosted Airflow.
*Rejected because:* plan §7 explicitly locks to self-hosted on GKE to avoid
managed lock-in and keep DAG code in-repo; Composer does not support the
KubernetesExecutor pattern that lets training tasks run as Volcano-scheduled
GPU pods; Composer v2 minimum cost ~$0.10/hr regardless of DAG activity.

### A3 — S3 as the MLflow artifact store
Cross-cloud artifact backend.
*Rejected because:* adds AWS credential dependency for a GCP-native workload;
violates Workload-Identity-only policy; increases read latency (cross-cloud
egress vs intra-GCP GCS).

### A4 — Local PersistentVolume for MLflow artifacts
GKE PVC-backed artifact store.
*Rejected because:* not HA, not multi-region accessible (ADR-0036 D5), no
audit-trail versioning, capacity-constrained for multi-GB TRT-LLM engines.

### A5 — Reuse an existing PostgreSQL instance
Share a Cloud SQL instance with application databases.
*Rejected because:* high-frequency training-metrics writes risk IOPS contention;
schema migrations have cross-service blast radius; connection pooling strategies
differ. See D3 above.

### A6 — Status quo (design-only, no implementation)
Keep the pipeline as documentation.
*Rejected because:* WS-B is the explicit gap; WS-C drift-trigger, WS-E audit
trail, and WS-F golden paths all depend on WS-B delivering a running pipeline.

## Consequences

### Positive
- Documented DAGs become running code with no rewrite — Airflow gitSync deploys
  the existing DAG catalogue directly from the repo.
- Signed, auditable artifacts per SOC2 change-management and the reproducibility
  invariants (Iceberg snapshot → run ID → adapter → Cosign signature).
- GCP-native, HA artifact store (GCS versioning + Workload Identity).
- Drift → retrain wired immediately when WS-C lands (`POST .../dagRuns`).
- `platform:system = ml-pipeline` on every resource enables FinOps attribution
  on the existing `$system` Grafana variable.

### Negative
- Self-hosted Airflow requires upgrade and patch management. Mitigated: pinned
  chart version, ArgoCD-managed upgrade path.
- KubernetesExecutor pod cold-start overhead for short tasks. Accepted:
  training/eval tasks are hours long; overhead is negligible.
- New Cloud SQL instance adds baseline DB cost. Accepted: cheaper than
  shared-instance IOPS contention.

### Risks
- **R2 — Airflow instability.** Dedicated node pool; PDB for scheduler; liveness
  probes; Alertmanager `airflow_dag_run_failed` route; pinned chart version.
- **R5 — MLflow SPOF.** `replicaCount: 2`, PDB `minAvailable: 1`, PostgreSQL
  backend, GCS artifact store. Full active-active MLflow HA is a tracked follow-up.
- **Secret rotation.** MLflow/Airflow DB credentials rotated via ESO
  ExternalSecret; `secret.forceRestart: true` triggers pod restarts on rotation.
- **Broken DAG prevention.** `ml-pipeline.yml` `validate` job runs
  `airflow dags parse` as a pre-train gate.

## Implementation notes

### Files created by this ADR

| File | Purpose |
|------|---------|
| `docs/adrs/0037-ml-cicd-pipeline-mlflow.md` | This ADR |
| `apps/infra/airflow/Chart.yaml` | Wrapper chart (Airflow dependency) |
| `apps/infra/airflow/values.yaml` | Helm values |
| `apps/infra/airflow/templates/argocd-app.yaml` | ArgoCD Application |
| `apps/infra/airflow/templates/external-secret.yaml` | ESO ExternalSecret |
| `apps/infra/airflow/templates/network-policy.yaml` | Stub NetworkPolicy |
| `apps/infra/airflow/dags/*.py` | DAG scaffolds (4 DAGs) |
| `apps/infra/mlflow/Chart.yaml` | Wrapper chart (MLflow dependency) |
| `apps/infra/mlflow/values.yaml` | Helm values |
| `apps/infra/mlflow/templates/argocd-app.yaml` | ArgoCD Application |
| `apps/infra/mlflow/templates/external-secret.yaml` | ESO ExternalSecret |
| `apps/infra/mlflow/templates/network-policy.yaml` | Stub NetworkPolicy |
| `terraform/modules/ml-artifact-store/` | GCS bucket + IAM + WI binding |
| `catalog/units/ml-artifact-store/terragrunt.hcl` | Catalog unit |
| `.github/workflows/ml-pipeline.yml` | ML CI/CD pipeline |

### Cloud SQL instance (D3) — out-of-band
Provisioned by DBA team using `terraform/modules/cloud-sql`. Connection host,
port, and credentials written to GCP Secret Manager at path
`/ml-pipeline/mlflow-db-password` and consumed via ESO ExternalSecret.

### MLflow HA follow-up (R5)
Configure sticky-session load balancing (`MLFLOW_HASH_ALGO`) when scaling
beyond 2 replicas. Document in `apps/infra/mlflow/README.md`.

### NetworkPolicy follow-up (D5)
`network-policies/ml-pipeline/00-default-deny.yaml` — default-deny
CiliumNetworkPolicy. Scoped allows:
- Airflow workers → MLflow tracking server (port 5000)
- MLflow tracking server → GCS (HTTPS 443)
- Airflow scheduler/webserver → Cloud SQL proxy (port 5432)
- Alertmanager → Airflow webserver (port 8080)

### Rollback
- Airflow/MLflow: ArgoCD `rollback` to previous Helm revision.
- GCS: object versioning allows artifact-level rollback.
- Pipeline: quality-gate job blocks promotion on eval failure; Kargo progressive
  rollout supports automated rollback on `post_deployment_smoke` failure.

## References

- Apache Airflow Helm Chart: <https://airflow.apache.org/docs/helm-chart/stable/index.html>
- Airflow KubernetesExecutor: <https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/executor/kubernetes.html>
- MLflow Tracking + Model Registry: <https://mlflow.org/docs/latest/tracking.html>
- MLflow GCS artifact store: <https://mlflow.org/docs/latest/tracking/artifacts-stores.html#google-cloud-storage>
- community-charts MLflow Helm chart: <https://github.com/community-charts/helm-charts/tree/main/charts/mlflow>
- GKE Workload Identity Federation: <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity>
- GCS uniform bucket-level access: <https://cloud.google.com/storage/docs/uniform-bucket-level-access>
- Cosign keyless signing: <https://docs.sigstore.dev/cosign/signing/overview/>
- Related ADRs: [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md),
  [ADR-0036](0036-gke-ml-infra-parity-multiregion.md),
  [ADR-0006](0006-argocd-for-gitops.md),
  [ADR-0008](0008-external-secrets-operator.md),
  [ADR-0016](0016-tier1-supply-chain-hardening.md)
- In-repo: `docs/transaction-analytics/04-training-pipeline.md`,
  `docs/gcp-ml-platform/IMPLEMENTATION_PLAN.md`,
  `docs/ci-rollout.md`,
  `.github/actions/cosign-sign`,
  `.github/actions/syft-sbom`,
  `apps/infra/opencost/` (ArgoCD app + ESO pattern),
  `terraform/modules/gcp-billing-budget/` (GCP module pattern)

---
*Doc-verified 2026-06-10 against official Apache Airflow Helm Chart, MLflow,
GCP GCS, and GKE Workload Identity documentation. Planning-only ADR — proposed,
not yet implemented. WS-B "ML CI/CD pipelines"; implementation apply-gated.*
