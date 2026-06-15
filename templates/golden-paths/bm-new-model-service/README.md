# Golden Path: New Model Service (Bare-Metal / Talos)

**Substrate:** Owned bare-metal GPU cluster on Talos Linux, two UK DCs
(primary + standby). See `docs/transaction-analytics/06-uk-datacenters.md`.

**ADRs cited:**
- ADR-0049 — Talos foundation, immutability, multi-DC
- ADR-0050 — GPU driver as Talos system extension (driver-less GPU Operator)
- ADR-0051 — Cilium LB-IPAM + BGP (service VIPs, no cloud LB)
- ADR-0052 — Rook-Ceph / MinIO (artifact store S3 endpoint, no GCS)
- ADR-0053 — InfiniBand/RoCEv2 GPU fabric
- ADR-0054 — Elasticity: fixed capacity + workload scale-to-zero
- ADR-0041 — Golden paths and collaboration (this document)
- ADR-0028 — Platform taxonomy labels (mandatory on every resource)
- ADR-0037 — ML CI/CD + MLflow registry (WS-B, re-targeted at MinIO/Ceph-RGW)
- ADR-0038 — Model observability / drift (WS-C, reused unchanged)
- ADR-0039 — Self-serve observability (WS-D, reused + BM panels)

This template wires a new ML model into the full bare-metal platform stack:
- **WS-B** (ADR-0037): `ml-pipeline-baremetal.yml` train->eval->register->deploy
  + MLflow registry (Postgres via CloudNativePG, artifacts in MinIO/Ceph-RGW)
- **WS-C** (ADR-0038): Evidently drift-exporter + whylogs profiler per-model namespace
- **WS-D** (ADR-0039): `grafana-self-serve` per-team dashboard + alert rules, including
  bare-metal-specific panels (Talos node health, IB/RoCE fabric, Cilium BGP, Ceph, etcd)

**Key differences from the GCP golden path (`templates/golden-paths/new-model-service/`):**

| Concern | GCP path | This bare-metal path |
|---------|---------|----------------------|
| Artifact store | GCS bucket (gs://...) | MinIO S3 endpoint or Ceph-RGW (s3://... at in-DC endpoint) |
| GPU Operator | driver managed by Operator | driver-less (driver baked into Talos system extension, ADR-0050) |
| Load balancer | Cloud LB / GKE Gateway | Cilium BGP VIP (ADR-0051) |
| Volcano queues | GCP-shaped | UK DC taxonomy: H100 -> training-default/bootstrap/urgent; H200 -> serving-vllm/eval-judge/engine-build/batch-rescore |
| Pipeline trigger | ml-pipeline.yml | ml-pipeline-baremetal.yml |

Backstage scaffolder mapping: `spec.type: model-service` (future, ADR-0034 deferred)

---

## Prerequisites

Before you start, confirm:

- [ ] Tenant namespace `tenant-{{TENANT_ID}}` exists (provisioned by the
  `bm-new-tenant` golden path, `templates/golden-paths/bm-new-tenant/`)
- [ ] `charts/tenant-bootstrap/` install has completed for your tenant
  (namespace, NetworkPolicy, ResourceQuota, Gatekeeper constraints, Kafka ACLs,
  per-tenant Vault KMS key are all in place)
- [ ] MinIO bucket `ml-artifacts-{{TENANT_ID}}` or Ceph-RGW bucket exists
  (provisioned by WS-B `terraform/modules/baremetal-ml-artifact-store`)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI`
  (`apps/infra/mlflow/` re-targeted at CloudNativePG + MinIO/Ceph-RGW)
- [ ] Airflow is reachable at `$AIRFLOW_BASE_URL`
  (`apps/infra/airflow/` deployed on the CPU pool of the bare-metal cluster)
- [ ] Grafana service account `grafana-sa-{{TEAM_SLUG}}` exists in Grafana
- [ ] Model training code lives under `models/{{MODEL_NAME}}/` or `adapters/{{MODEL_NAME}}/`
  (triggers `.github/workflows/ml-pipeline-baremetal.yml` on push)
- [ ] You have read `docs/contracts/model-api-contract.md` and
  `docs/contracts/bm-model-api-contract-addendum.md` and your model schema matches both
- [ ] Contract sign-off obtained from Data Eng, Backend, and Frontend leads
  (see `docs/golden-paths/bm-RACI-and-handoffs.md` -- required before staging promotion)
- [ ] Your VolcanoJob YAML sets `spec.queue` to one of the UK DC queues:
  H100 training: `training-default`, `training-bootstrap`, `training-urgent`
  H200 inference: `serving-vllm`, `eval-judge`, `engine-build`, `batch-rescore`

---

## Step 1 -- Substitute placeholders

Copy this template directory to a working location and substitute all placeholders.
Use `envsubst` or `sed`:

```bash
export MODEL_NAME="fraud-uk"              # lower-kebab; used in DAG IDs, MLflow model name
export MODEL_NAMESPACE="fraud-uk"         # Kubernetes namespace for this model
export TENANT_ID="acme"                   # tenant ID (namespace is tenant-acme)
export TENANT="tenant-acme"              # full tenant label (ADR-0038)
export DOMAIN="hft"                       # one of: hft, solana, insurance, rtb
export TEAM_NAME="ML Fraud UK"           # human-readable
export TEAM_SLUG="team-ml-fraud-uk"      # lower-kebab
export TEAM_OWNER="team-ml-fraud-uk"     # ADR-0028 platform.owner
export PLATFORM_ENV="production"          # production | staging | dev | sandbox
export MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000"
export MINIO_BUCKET="ml-artifacts-${TENANT_ID}"
export VOLCANO_QUEUE="training-default"

mkdir -p out
for f in argocd-application.yaml values-ml-monitoring.yaml values-grafana-self-serve.yaml ml-pipeline-trigger.yaml volcanjob-training.yaml; do
  envsubst < "$f" > "out/${f}"
done

# Verify no raw {{}} remain
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

In the Python DAG / VolcanoJob files, replace `# SUBSTITUTE:` blocks manually.

---

## Step 2 -- Add the model to the ML pipeline trigger

Review `out/ml-pipeline-trigger.yaml` and dispatch the first pipeline run:

```bash
gh workflow run ml-pipeline-baremetal.yml \
  --ref main \
  --field model="${MODEL_NAME}" \
  --field environment="${PLATFORM_ENV}" \
  --field tenant="${TENANT_ID}"
```

The pipeline:
1. Submits a VolcanoJob on the H100 queue (`spec.queue: {{VOLCANO_QUEUE}}`)
2. Runs `eval_adapter_debate` on `eval-judge` H200 queue
3. Quality gate: `win_rate >= 0.55`
4. Registers signed artifact in MLflow (MinIO/Ceph-RGW S3 backend)
5. SBOM (syft) + cosign sign (same composites as `.github/actions/sign-image/`)
6. Kargo promotion: dev (auto) -> staging (reviewer gate) -> prod (manual gate)

---

## Step 3 -- Configure drift monitoring (WS-C)

Add your model to `apps/infra/ml-monitoring/values.yaml` by appending the
content of `out/values-ml-monitoring.yaml` under `modelNamespaces:`.

The bare-metal drift-exporter reads the reference dataset from the MinIO/Ceph-RGW
S3 endpoint instead of GCS. Set `s3Endpoint` to the in-DC address (UK data residency):

```yaml
# apps/infra/ml-monitoring/values.yaml (append under modelNamespaces:)
- namespace: "{{MODEL_NAMESPACE}}"
  referenceBucketUri: "s3://{{MINIO_BUCKET}}/{{MODEL_NAME}}/{{TENANT_ID}}/{{DOMAIN}}/reference.parquet"
  s3Endpoint: "{{MINIO_ENDPOINT}}"   # in-DC S3 endpoint; NOT external AWS
```

A drift alert routes: Alertmanager -> PagerDuty -> Airflow REST retrain trigger
(POST .../train_domain_adapter/dagRuns on the in-DC Airflow, same path as GCP).

---

## Step 4 -- Configure self-serve observability (WS-D)

Commit `out/values-grafana-self-serve.yaml` at:
```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml
```

The bare-metal Grafana values enable the **BM-specific starter panels**
(`baremetal.*` section in `values-grafana-self-serve.yaml`):
- Talos node health (machine API liveness, kubelet ready)
- InfiniBand / RoCEv2 fabric (NCCL all-reduce bandwidth, NVLink counters per
  `ai-sre/knowledge/nccl-troubleshooting.md`)
- Cilium BGP session state (ToR peering, per `ai-sre/knowledge/cilium-bgp-issues.md`)
- Ceph cluster health (HEALTH_OK / HEALTH_WARN, OSD up/in)
- etcd latency + quorum (control-plane health -- absent on managed-K8s paths)

Then commit `out/argocd-application.yaml` at:
```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/argocd-application.yaml
```

---

## Step 5 -- Contract sign-off

Before the Kargo staging promotion gate:

1. Author a contract instance YAML in `docs/contracts/` following
   `docs/contracts/model-api-contract.md` **and** the BM addendum at
   `docs/contracts/bm-model-api-contract-addendum.md` (MinIO endpoint, Volcano
   queue, IB fabric requirements).
2. Open a PR with the contract YAML.
3. Obtain sign-off from: Data Engineering + Backend/Frontend + Platform/SRE
   (see `docs/golden-paths/bm-RACI-and-handoffs.md` Handoff H5 -- required gate).

---

## Step 6 -- Verify ADR-0028 labels

Every resource you commit must carry the platform taxonomy labels.
Use `tests/opa/platform_tags_baremetal.rego` (WS-E) to check at plan time:

```bash
# Kubernetes manifests must carry (dotted form):
#   platform.system / platform.component / platform.env
#   platform.owner  / platform.managed-by
#
# Terraform resources (talos_* / kubernetes_manifest) must carry (underscore form):
#   platform_system / platform_component / platform_env
#   platform_owner  / platform_managed_by
```

The bare-metal OPA profile (`platform_tags_baremetal.rego`) flags missing labels
on `talos_*` and `kubernetes_manifest` resources at plan time. The AWS-shaped
policy (`platform_tags.rego`) does NOT cover these resource types.

---

## Backstage future mapping

When ADR-0034 revisit criteria are met (see `docs/golden-paths/bm-RACI-and-handoffs.md` ss5):
- `spec.type: model-service`
- `spec.lifecycle: production | staging`
- `spec.owner: {{TEAM_SLUG}}`
- `spec.system: ml-platform-baremetal`
- `spec.dependsOn: [mlflow-baremetal, airflow-baremetal, minio-artifacts, evidently-drift-exporter]`

---

## References

- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (WS-A foundation)
- `docs/adrs/0050-talos-gpu-driver-system-extensions.md` (GPU driver via Talos extension)
- `docs/adrs/0051-baremetal-networking-cilium-lb-bgp.md` (Cilium BGP LB)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (storage substrate)
- `docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md` (IB/RoCE fabric)
- `docs/adrs/0054-baremetal-elasticity-node-lifecycle.md` (fixed capacity model)
- `docs/adrs/0037-ml-cicd-pipeline-mlflow.md` (WS-B ML pipeline)
- `docs/adrs/0038-ml-observability-drift.md` (WS-C drift monitoring)
- `docs/adrs/0039-self-serve-observability.md` (WS-D self-serve)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F, this document)
- `docs/contracts/model-api-contract.md` (base contract spec)
- `docs/contracts/bm-model-api-contract-addendum.md` (BM-specific addendum)
- `docs/golden-paths/bm-RACI-and-handoffs.md` (RACI and handoff protocol)
- `docs/transaction-analytics/06-uk-datacenters.md` (UK DC design fiction)
- `ai-sre/knowledge/nccl-troubleshooting.md` (NCCL/IB runbook)
- `ai-sre/knowledge/cilium-bgp-issues.md` (BGP runbook)
- `ai-sre/knowledge/gpu-driver-updates.md` (GPU driver checklist)
- `.github/workflows/ml-pipeline-baremetal.yml` (WS-B BM pipeline)
- `templates/golden-paths/bm-new-tenant/` (provision tenant namespace first)
