# Golden Path: New ML Pipeline / Airflow DAG (Bare-Metal / Talos)

**Substrate:** Owned bare-metal GPU cluster on Talos Linux, two UK DCs.
See `docs/transaction-analytics/06-uk-datacenters.md`.

**ADRs cited:**
- ADR-0049 -- Talos foundation, immutability, multi-DC
- ADR-0052 -- Rook-Ceph / MinIO (artifact store, no GCS)
- ADR-0053 -- InfiniBand/RoCEv2 GPU fabric (VolcanoJob DRA claim)
- ADR-0054 -- Elasticity: fixed capacity + Volcano queue discipline
- ADR-0041 -- Golden paths and collaboration (this document)
- ADR-0028 -- Platform taxonomy labels (mandatory on every resource)
- ADR-0037 -- ML CI/CD + MLflow registry (WS-B, re-targeted at MinIO/Ceph-RGW)
- ADR-0038 -- Model observability / drift (WS-C, reused unchanged)

This template creates a new Airflow DAG on the bare-metal cluster, mirroring the
WS-B (ADR-0037) DAG shape. The DAG:
- Submits work as a **VolcanoJob** on the appropriate UK DC GPU queue (H100/H200 pool)
- Registers artifacts in MLflow backed by **MinIO/Ceph-RGW** (not GCS)
- Emits drift metrics so they are scrapeable by WS-C Evidently + whylogs

**Key differences from the GCP golden path (`templates/golden-paths/new-ml-pipeline/`):**

| Concern | GCP path | This bare-metal path |
|---------|---------|----------------------|
| Work submission | KubernetesPodOperator or GKE-native | VolcanoJob on UK DC queue taxonomy |
| GPU queue | GCP-shaped | H100: training-default/bootstrap/urgent; H200: serving-vllm/eval-judge/engine-build/batch-rescore |
| Artifact store | GCS (gs://) | MinIO/Ceph-RGW (s3://, in-DC) |
| Pipeline workflow | ml-pipeline.yml | ml-pipeline-baremetal.yml |
| GPU+NIC scheduling | cloud-native | DRA ResourceClaimTemplate (ADR-0053) |

Backstage scaffolder mapping: `spec.type: ml-pipeline` (future, ADR-0034 deferred)

---

## When to use this template

Use this golden path when you need a **net-new Airflow DAG** that is:
- Not one of the four canonical WS-B DAGs (`train_domain_adapter`, `eval_adapter_debate`,
  `mine_templates`, `promote_to_edge`)
- Running GPU work on the UK DC bare-metal cluster
- Processing a new data domain or running a periodic batch ML job
- Registering its own model artifacts in MLflow (MinIO/Ceph-RGW backend)
- Expected to emit distribution metrics for WS-C drift monitoring

If you are adding a model that uses the existing canonical DAGs, use the
`bm-new-model-service` golden path instead.

---

## Prerequisites

- [ ] Tenant namespace `tenant-{{TENANT_ID}}` exists (provisioned by `bm-new-tenant`)
- [ ] MinIO bucket `ml-artifacts-{{TENANT_ID}}` or Ceph-RGW bucket exists
  (provisioned by WS-B `terraform/modules/baremetal-ml-artifact-store`)
- [ ] Airflow is reachable at `$AIRFLOW_BASE_URL` (in-DC CPU pool, WS-B)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI` (WS-B)
- [ ] WS-C `ml-monitoring` namespace and Pushgateway exist (`apps/infra/ml-monitoring/`)
- [ ] You know which Volcano queue you need (H100 vs H200 pool; default vs urgent)
- [ ] Your DAG code will live in `apps/infra/airflow/dags/{{DAG_NAME}}.py`
  (Airflow gitSync picks it up automatically from the repo)

---

## Step 1 -- Substitute placeholders

```bash
export DAG_NAME="my_custom_bm_pipeline"   # snake_case; Airflow dag_id
export MODEL_NAME="my-model"              # lower-kebab; MLflow registry name
export TENANT_ID="acme"                   # tenant ID (namespace: tenant-acme)
export TENANT="tenant-acme"              # full label (ADR-0038)
export DOMAIN="hft"                       # hft | solana | insurance | rtb
export TEAM_OWNER="team-ml-platform"     # ADR-0028 platform.owner
export PLATFORM_ENV="production"          # production | staging | dev | sandbox
export MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000"
export MINIO_BUCKET="ml-artifacts-${TENANT_ID}"
# Choose queue: H100 training pool or H200 inference pool
export VOLCANO_QUEUE="training-default"   # or training-bootstrap, training-urgent, etc.
export GPU_REPLICAS="8"                   # gang size (DGX H100: 8 GPUs per node)

mkdir -p out
for f in argocd-application.yaml; do
  envsubst < "$f" > "out/${f}"
done

# DAG file: substitute manually (see Step 2)
cp dag_template.py apps/infra/airflow/dags/${DAG_NAME}.py

# Verify no raw {{}} remain in YAML output
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

---

## Step 2 -- Implement the DAG tasks

Open `apps/infra/airflow/dags/{{DAG_NAME}}.py` and implement the `# SCAFFOLD`
task bodies:

| Task | What to implement |
|------|-------------------|
| `ingest_data` | Load from MinIO/Ceph-RGW (boto3 with in-DC endpoint), Iceberg snapshot, Kafka, etc. |
| `submit_volcano_job` | Render VolcanoJob YAML with spec.queue={{VOLCANO_QUEUE}} and submit via k8s API |
| `register_results` | Write metrics + artifacts to MLflow (s3:// URI, in-DC endpoint) |
| `emit_drift_metrics` | Push feature distributions to Prometheus Pushgateway |

### VolcanoJob queue selection (UK DC taxonomy)

Pick the queue that matches your workload type:

| Queue | Pool | Weight | Cap | Use case |
|-------|------|--------|-----|----------|
| `training-default` | H100 | 100 | - | Regular tenant retrains |
| `training-bootstrap` | H100 | 30 | - | New-tenant initial fine-tunes |
| `training-urgent` | H100 | 200 | 2 jobs | Drift-triggered or incident-response |
| `serving-vllm` | H200 | 150 | - | vLLM multi-LoRA for internal/batch |
| `eval-judge` | H200 | 200 | - | LLM-as-judge debate |
| `engine-build` | H200 | 80 | - | TRT-LLM compilation jobs |
| `batch-rescore` | H200 | 50 | - | Reprocessing historical data |

The VolcanoJob must also include a DRA ResourceClaimTemplate for GPU + IB NIC
(ADR-0053 one-DRA-model pattern, provisioned by `baremetal-gpu-scheduling` module).

### MinIO/MLflow integration pattern

```python
import os
import mlflow
import boto3

# Credentials from Vault / ESO ExternalSecret -- never hardcoded.
s3_client = boto3.client(
    "s3",
    endpoint_url=os.environ["MINIO_ENDPOINT"],   # in-DC, not external AWS
    aws_access_key_id=os.environ["MINIO_ACCESS_KEY"],
    aws_secret_access_key=os.environ["MINIO_SECRET_KEY"],
)

mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
mlflow.set_experiment("{{DAG_NAME}}")
# artifact_uri uses s3:// with in-DC endpoint -- NOT gs://
with mlflow.start_run():
    mlflow.log_param("volcano_queue", os.environ["VOLCANO_QUEUE"])
    mlflow.log_artifact(local_model_path)
```

---

## Step 3 -- Verify ADR-0028 labels

Every K8s resource (VolcanoJob, ConfigMap) submitted by your DAG must carry the
platform taxonomy labels. The BM OPA profile (`tests/opa/platform_tags_baremetal.rego`)
enforces this at plan time:

```yaml
metadata:
  labels:
    platform.system: "ml-pipeline"
    platform.component: "airflow"
    platform.env: "{{PLATFORM_ENV}}"
    platform.owner: "{{TEAM_OWNER}}"
    platform.managed-by: "argocd"
```

---

## References

- `docs/adrs/0049-baremetal-gpu-k8s-talos-foundation-multidc.md` (WS-A)
- `docs/adrs/0052-baremetal-storage-rook-ceph.md` (MinIO/Ceph-RGW)
- `docs/adrs/0053-baremetal-gpu-fabric-roce-infiniband.md` (DRA + IB)
- `docs/adrs/0054-baremetal-elasticity-node-lifecycle.md` (Volcano queue discipline)
- `docs/adrs/0037-ml-cicd-pipeline-mlflow.md` (WS-B ML pipeline)
- `docs/adrs/0038-ml-observability-drift.md` (WS-C drift monitoring)
- `docs/adrs/0041-golden-paths-collaboration.md` (WS-F)
- `docs/transaction-analytics/06-uk-datacenters.md` (UK DC queue taxonomy)
- `ai-sre/knowledge/nccl-troubleshooting.md` (NCCL/IB pre-flight)
- `docs/golden-paths/bm-RACI-and-handoffs.md` (RACI and handoff protocol)
- `templates/golden-paths/bm-new-tenant/` (provision tenant namespace first)
- `templates/golden-paths/bm-new-model-service/` (for canonical DAG model services)
