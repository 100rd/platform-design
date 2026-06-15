# Golden Path: AWS ML -- New ML Pipeline (Airflow DAG)

> **Platform:** AWS EKS GPU ML cluster (ADR-0044 / ADR-0048)
> **ADR gates:** ADR-0041 (template approach), ADR-0048 (AWS backends)
> **GCP etalon:** `templates/golden-paths/new-ml-pipeline/` (GCP/GKE variant)
>
> This is the **AWS-flavoured** golden path. The DAG structure, MLflow integration
> pattern, and WS-C drift metric push are **identical** to the GCP etalon
> (inherited from ADR-0037/0038 via ADR-0048). Only the cloud-specific wiring
> differs: S3 artifact store + EKS Pod Identity/ABAC, ECR, AWS Secrets Manager.

This template creates a new Airflow DAG that mirrors the WS-B (ADR-0048 <- ADR-0037)
DAG shape. It registers artifacts in MLflow (RDS Postgres backend, S3 artifact store)
and emits drift metrics so they are scrapeable by WS-C (ADR-0048 <- ADR-0038)
Evidently + whylogs.

Backstage scaffolder mapping: `spec.type: ml-pipeline`
(see "Backstage future mapping" below; ADR-0034 remains deferred).

Chart versions verified against:

- `apps/infra/airflow/dags/` (WS-B) as of 2026-06-15
- `apps/infra/mlflow/` (WS-B, S3 + RDS) as of 2026-06-15

---

## When to use this template

Use this golden path when you need a **net-new Airflow DAG** that is:

- Not one of the four canonical WS-B DAGs (`train_domain_adapter`, `eval_adapter_debate`,
  `mine_templates`, `promote_to_edge`)
- Processing a new data domain or running a periodic batch ML job on the AWS EKS ML cluster
- Registering its own model artifacts in MLflow (S3 artifact store + RDS backend)
- Expected to emit distribution metrics for WS-C monitoring

If you are adding a new **model** that uses the existing canonical DAGs, use the
`aws-ml-new-model-service` golden path instead
(`templates/golden-paths/aws-ml-new-model-service/`).

---

## Prerequisites

- [ ] Airflow is deployed at `$AIRFLOW_BASE_URL` (WS-B `apps/infra/airflow/`)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI` (WS-B `apps/infra/mlflow/`)
- [ ] S3 bucket `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}` exists with
  `platform:system = ml-pipeline` tag (ADR-0028) and the correct Pod Identity IAM role
- [ ] Your task pod ServiceAccount has a Pod Identity binding to an IAM role with
  `s3:PutObject` on the artifacts prefix (ADR-0018 + ADR-0048 D2)
- [ ] WS-C `ml-monitoring` namespace and Pushgateway exist (`apps/infra/ml-monitoring/`)
- [ ] Your DAG code will live in `apps/infra/airflow/dags/{{DAG_NAME}}.py`
  (Airflow gitSync picks it up automatically)
- [ ] ECR repository `{{ECR_REGISTRY}}/{{MODEL_NAME}}` exists
  (pull-through cache covers upstream bases, ADR-0029)

---

## Step 1 -- Substitute placeholders

```bash
# AWS-specific
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"
export S3_MLFLOW_ARTIFACTS_BUCKET="mlflow-artifacts-prod-${AWS_ACCOUNT_ID}"
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Pipeline identity
export DAG_NAME="my_custom_pipeline"        # snake_case; becomes the Airflow dag_id
export MODEL_NAME="my-model"                # lower-kebab; MLflow model registry name
export TENANT="tenant-acme"                 # ADR-0038 multi-tenant label
export DOMAIN="hft"                         # one of: hft, solana, insurance, rtb
export TEAM_OWNER="team-ml-platform"        # ADR-0028 platform:owner
export PLATFORM_ENV="production"            # production | staging | dev | sandbox

# Copy the DAG template
cp dag_template.py apps/infra/airflow/dags/${DAG_NAME}.py

# Substitute YAML placeholders
mkdir -p out
envsubst < argocd-application.yaml > out/argocd-application.yaml

# Verify no raw {{}} remain in the YAML output
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

In the Python DAG file, replace the `# SUBSTITUTE:` comment blocks manually
(shell variable substitution in Python source is fragile).

---

## Step 2 -- Implement the DAG tasks

Open `apps/infra/airflow/dags/{{DAG_NAME}}.py` and implement the four `# SCAFFOLD`
task bodies:

| Task | What to implement |
|------|-------------------|
| `ingest_data` | Load data from source (S3 snapshot, Iceberg on S3, Kinesis, DynamoDB, etc.) |
| `run_batch_job` | Submit work: VolcanoJob for GPU tasks, PythonOperator for CPU tasks |
| `register_results` | Write metrics + artifacts to MLflow (S3 + RDS, see MLflow integration below) |
| `emit_drift_metrics` | Push feature distributions to Prometheus Pushgateway (see WS-C below) |

### MLflow integration (AWS)

The `register_results` task uses:

- `MLFLOW_TRACKING_URI` env var (injected from ESO ExternalSecret at
  `apps/infra/mlflow/templates/external-secret.yaml` -- sourced from AWS Secrets Manager)
- `AWS_DEFAULT_REGION` env var (set by the Pod Identity SDK automatically)
- Experiment name convention: `{{TENANT}}/{{DOMAIN}}/{{DAG_NAME}}`
- Model registry name: `{{MODEL_NAME}}`
- Artifacts stored at: `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/{{MODEL_NAME}}/{{TENANT}}/{{DOMAIN}}/`

```python
import mlflow
import os

mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
mlflow.set_experiment(f"{tenant}/{domain}/{dag_name}")

with mlflow.start_run(run_name=f"{tenant}/{domain}"):
    mlflow.log_params({"tenant": tenant, "domain": domain})
    mlflow.log_metrics({"accuracy": 0.0, "loss": 0.0})  # replace with real metrics
    # mlflow.pytorch.log_model(model, "model")           # writes to S3 via Pod Identity
    mlflow.register_model(
        f"runs:/{mlflow.active_run().info.run_id}/model",
        model_name,
    )
```

**No static AWS credentials needed**: the Airflow task pod uses EKS Pod Identity
(ADR-0018 + ADR-0048 D2). The `aws-ml-artifact-store` IAM role is bound to the
task ServiceAccount via a Pod Identity association.

### Drift metrics (WS-C integration)

The `emit_drift_metrics` task pushes to the shared Pushgateway (cluster-agnostic,
identical to the GCP etalon):

```python
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

registry = CollectorRegistry()
g = Gauge(
    "ml_monitoring_dataset_drift_score",
    "Evidently dataset drift score",
    ["model_name", "tenant", "domain"],
    registry=registry,
)
g.labels(model_name=model_name, tenant=tenant, domain=domain).set(drift_score)

push_to_gateway(
    "prometheus-pushgateway.ml-monitoring.svc.cluster.local:9091",
    job=dag_name,
    registry=registry,
)
```

Labels must match ADR-0038 D1: `model_name`, `tenant`, `domain`.

### GPU task executor config (AWS: Karpenter + Volcano)

For GPU tasks on the `aws-eks-gpu-*` cluster, update `executor_config`:

```python
_GPU_EXECUTOR_CONFIG = {
    "pod_override": {
        "spec": {
            # Volcano gang scheduler (ADR-0044 D3 / ADR-0048 D1)
            "schedulerName": "volcano",
            # AWS EKS Karpenter GPU nodepool label (ADR-0046)
            # Replace cloud.google.com/gke-nodepool with karpenter.sh/nodepool
            "nodeSelector": {
                "karpenter.sh/nodepool": "gpu-p4d-spot",   # adjust to your pool
                "nvidia.com/gpu.present": "true",
            },
            "tolerations": [
                {"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}
            ],
        }
    }
}
```

**AWS delta vs GCP etalon:** use `karpenter.sh/nodepool` (not `cloud.google.com/gke-nodepool`).

---

## Step 3 -- Validate the DAG locally

```bash
# Install Airflow in a venv (match the chart-pinned version)
pip install "apache-airflow==2.9.*" --constraint \
  "https://raw.githubusercontent.com/apache/airflow/constraints-2.9.3/constraints-3.11.txt"

# Parse the DAG (should complete without errors or import warnings)
python apps/infra/airflow/dags/{{DAG_NAME}}.py
airflow dags list-import-errors
```

---

## Step 4 -- Open the PR

PR checklist:

- [ ] `apps/infra/airflow/dags/{{DAG_NAME}}.py` included
- [ ] `yamllint -c .yamllint.yml out/argocd-application.yaml` passes
- [ ] DAG parses without errors (`airflow dags list-import-errors`)
- [ ] MLflow experiment name follows `{{TENANT}}/{{DOMAIN}}/{{DAG_NAME}}`
- [ ] Artifact store path is `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/...` (not `gs://`)
- [ ] No static AWS credentials in DAG code (Pod Identity only, ADR-0018)
- [ ] Drift metrics pushed to Pushgateway use labels `model_name`, `tenant`, `domain`
- [ ] GPU executor config uses `karpenter.sh/nodepool` (not `cloud.google.com/gke-nodepool`)
- [ ] ADR-0028 labels in all Kubernetes manifests and AWS resources
- [ ] Link to MLflow experiment URL after first DAG run

---

## Platform support

- ADR-0044: EKS GPU cluster / Volcano / Karpenter pool labels
- ADR-0048: AWS ML CI/CD, S3 artifact store, RDS, ECR
- ADR-0038: drift metrics + Pushgateway integration
- ADR-0041: this template (golden-path structure)
- ADR-0018: EKS Pod Identity (no static credentials in pods)

---

## Backstage future mapping

```yaml
# catalog-info.yaml (future -- do not deploy before ADR-0034 revisit)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: aws-ml-new-pipeline
spec:
  type: ml-pipeline
  parameters:
    - title: AWS identity
      properties:
        awsAccountId:       # -> {{AWS_ACCOUNT_ID}}
        awsRegion:          # -> {{AWS_REGION}}
        s3ArtifactsBucket:  # -> {{S3_MLFLOW_ARTIFACTS_BUCKET}}
        ecrRegistry:        # -> {{ECR_REGISTRY}}
    - title: Pipeline identity
      properties:
        dagName:     # -> {{DAG_NAME}}
        modelName:   # -> {{MODEL_NAME}}
        tenant:      # -> {{TENANT}}
        domain:      # -> {{DOMAIN}}
        teamOwner:   # -> {{TEAM_OWNER}}
        platformEnv: # -> {{PLATFORM_ENV}}
  steps:
    - id: fetch-template
      action: fetch:template
      input:
        url: ./templates/golden-paths/aws-ml-new-pipeline
    - id: publish
      action: publish:github:pull-request
    - id: register
      action: catalog:register
```
