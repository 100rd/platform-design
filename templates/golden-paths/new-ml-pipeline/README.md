# Golden Path: New ML Pipeline (Airflow DAG)

This template creates a new Airflow DAG that mirrors the WS-B (ADR-0037) DAG shape.
It registers artifacts in MLflow and emits drift metrics so they are scrapeable by
WS-C (ADR-0038) Evidently + whylogs.

Backstage scaffolder mapping: `spec.type: ml-pipeline`

Chart versions verified against:
- `apps/infra/airflow/dags/` (WS-B) — DAG scaffolds as of 2026-06-10
- `apps/infra/mlflow/` (WS-B) — MLflow chart as of 2026-06-10

---

## When to use this template

Use this golden path when you need a **net-new Airflow DAG** that is:
- Not one of the four canonical WS-B DAGs (`train_domain_adapter`, `eval_adapter_debate`,
  `mine_templates`, `promote_to_edge`)
- Processing a new data domain or running a periodic batch ML job
- Registering its own model artifacts in MLflow
- Expected to emit distribution metrics for WS-C monitoring

If you are adding a new **model** that uses the existing canonical DAGs, use the
`new-model-service` golden path instead (`templates/golden-paths/new-model-service/`).

---

## Prerequisites

- [ ] Airflow is deployed at `$AIRFLOW_BASE_URL` (WS-B `apps/infra/airflow/`)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI` (WS-B `apps/infra/mlflow/`)
- [ ] WS-C `ml-monitoring` namespace and Pushgateway exist (`apps/infra/ml-monitoring/`)
- [ ] Your DAG code will live in `apps/infra/airflow/dags/{{DAG_NAME}}.py`
  (Airflow gitSync picks it up automatically from the repo)

---

## Step 1 — Substitute placeholders

```bash
export DAG_NAME="my_custom_pipeline"        # snake_case; becomes the Airflow dag_id
export MODEL_NAME="my-model"                # lower-kebab; MLflow model registry name
export TENANT="tenant-acme"                 # ADR-0038 multi-tenant label
export DOMAIN="hft"                         # one of: hft, solana, insurance, rtb
export TEAM_OWNER="team-ml-platform"        # ADR-0028 platform.owner
export PLATFORM_ENV="production"            # production | staging | dev | sandbox

# Copy the DAG template
cp dag_template.py apps/infra/airflow/dags/${DAG_NAME}.py

# Substitute non-Python placeholder YAML
mkdir -p out
envsubst < argocd-application.yaml > out/argocd-application.yaml

# Verify no raw {{}} remain in the YAML output
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

In the Python DAG file, replace the `# SUBSTITUTE:` comment blocks manually
(shell variable substitution in Python source is fragile).

---

## Step 2 — Implement the DAG tasks

Open `apps/infra/airflow/dags/{{DAG_NAME}}.py` and implement the four `# SCAFFOLD`
task bodies:

| Task | What to implement |
|------|-------------------|
| `ingest_data` | Load data from source (Iceberg snapshot, GCS, Pub/Sub, BigQuery, etc.) |
| `run_batch_job` | Submit work: VolcanoJob for GPU tasks, PythonOperator for CPU tasks |
| `register_results` | Write metrics + artifacts to MLflow (see MLflow integration below) |
| `emit_drift_metrics` | Push feature distributions to Prometheus Pushgateway (see below) |

### MLflow integration

The `register_results` task uses:
- `MLFLOW_TRACKING_URI` env var (injected from ESO ExternalSecret at
  `apps/infra/mlflow/templates/external-secret.yaml`)
- Experiment name convention: `{{TENANT}}/{{DOMAIN}}/{{DAG_NAME}}`
- Model registry name: `{{MODEL_NAME}}`

```python
import mlflow
import os

mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
mlflow.set_experiment(f"{tenant}/{domain}/{dag_name}")

with mlflow.start_run(run_name=f"{tenant}/{domain}/{dag_name}"):
    mlflow.log_params({"tenant": tenant, "domain": domain})
    mlflow.log_metrics({"accuracy": 0.0, "loss": 0.0})  # replace with real metrics
    # mlflow.pytorch.log_model(model, "model")
    mlflow.register_model(
        f"runs:/{mlflow.active_run().info.run_id}/model",
        model_name,
    )
```

### Drift metrics (WS-C integration)

The `emit_drift_metrics` task pushes to the shared Pushgateway:

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

Labels must match ADR-0038 §D1: `model_name`, `tenant`, `domain`.

---

## Step 3 — Validate the DAG locally

```bash
# Install Airflow in a venv (match the chart-pinned version)
pip install "apache-airflow==2.9.*" --constraint \
  "https://raw.githubusercontent.com/apache/airflow/constraints-2.9.3/constraints-3.11.txt"

# Parse the DAG (should complete without errors or import warnings)
python apps/infra/airflow/dags/{{DAG_NAME}}.py
airflow dags list-import-errors
```

---

## Step 4 — Open the PR

PR checklist:
- [ ] `apps/infra/airflow/dags/{{DAG_NAME}}.py` included
- [ ] `yamllint -c .yamllint.yml out/argocd-application.yaml` passes
- [ ] DAG parses without errors (`airflow dags list-import-errors`)
- [ ] MLflow experiment name follows `{{TENANT}}/{{DOMAIN}}/{{DAG_NAME}}`
- [ ] Drift metrics pushed to Pushgateway use labels `model_name`, `tenant`, `domain`
- [ ] ADR-0028 labels in all Kubernetes manifests
- [ ] Link to MLflow experiment after first DAG run

---

## Platform support

- ADR-0037 (WS-B): Airflow + MLflow architecture
- ADR-0038 (WS-C): drift metrics + Pushgateway integration
- ADR-0041 (WS-F): this template

---

## Backstage future mapping

```yaml
# catalog-info.yaml (future — do not deploy before ADR-0034 revisit)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-ml-pipeline
spec:
  type: ml-pipeline
  parameters:
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
        url: ./templates/golden-paths/new-ml-pipeline
    - id: publish
      action: publish:github:pull-request
    - id: register
      action: catalog:register
```
