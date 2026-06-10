# Golden Path: New Model Service

This template wires a new ML model into the full platform stack:
- **WS-B** (ADR-0037): `ml-pipeline.yml` train→eval→register→deploy + MLflow registry
- **WS-C** (ADR-0038): Evidently drift-exporter + whylogs profiler per-model namespace
- **WS-D** (ADR-0039): `grafana-self-serve` per-team dashboard + alert rules

Backstage scaffolder mapping: `spec.type: model-service`
(see "Backstage future mapping" at the bottom of this file).

Chart versions verified against:
- `apps/infra/ml-monitoring` (WS-C) — chart as of 2026-06-10
- `apps/infra/grafana-self-serve` (WS-D) — chart as of 2026-06-10
- `.github/workflows/ml-pipeline.yml` (WS-B) — as of 2026-06-10

---

## Prerequisites

Before you start, confirm:

- [ ] Namespace `{{MODEL_NAMESPACE}}` exists in the cluster
  (or ask Platform to create it via `kubectl create namespace {{MODEL_NAMESPACE}}`)
- [ ] GCS bucket `gs://{{GCS_MLFLOW_ARTIFACTS_BUCKET}}` exists
  (provisioned by WS-B `terraform/modules/ml-artifact-store`)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI`
  (deployed by WS-B `apps/infra/mlflow/`)
- [ ] Airflow is reachable at `$AIRFLOW_BASE_URL`
  (deployed by WS-B `apps/infra/airflow/`)
- [ ] Grafana service account `grafana-sa-{{TEAM_SLUG}}` exists in Grafana
  (create via Grafana UI or API before ArgoCD sync)
- [ ] Model training code lives under `models/{{MODEL_NAME}}/` or `adapters/{{MODEL_NAME}}/`
  (triggers `.github/workflows/ml-pipeline.yml` on push)
- [ ] You have read `docs/contracts/model-api-contract.md` and your model's request/response
  schema matches the platform contract
- [ ] Contract sign-off obtained from Data Eng, Backend, and Frontend leads
  (see `docs/golden-paths/RACI-and-handoffs.md` — required before staging promotion)

---

## Step 1 — Substitute placeholders

Copy this template directory to a working location and substitute all placeholders.
Use `envsubst` or `sed`:

```bash
# Set your values
export MODEL_NAME="fraud-uk"              # lower-kebab; used in DAG IDs, MLflow model name
export MODEL_NAMESPACE="fraud-uk"         # Kubernetes namespace for this model
export TEAM_SLUG="team-ml-fraud"          # lower-kebab; used in Grafana folder + alert prefix
export TEAM_NAME="ML Fraud"              # human-readable
export TEAM_OWNER="team-ml-fraud"        # ADR-0028 platform.owner
export TENANT="tenant-acme"              # ADR-0038 multi-tenant label
export DOMAIN="hft"                      # one of: hft, solana, insurance, rtb
export PLATFORM_ENV="production"         # production | staging | dev | sandbox
export GCS_MLFLOW_ARTIFACTS_BUCKET="mlflow-artifacts-prod-yourproject"

# Substitute in all template files (dry-run first)
mkdir -p out
for f in values-grafana-self-serve.yaml values-ml-monitoring.yaml \
          ml-pipeline-trigger.yaml argocd-application.yaml; do
  envsubst < "$f" > "out/${f}"
done
```

Verify no `{{` remain:
```bash
grep -r '{{' out/ && echo "UNSUBSTITUTED PLACEHOLDERS FOUND" || echo "OK"
```

---

## Step 2 — Wire the training pipeline (WS-B)

The file `ml-pipeline-trigger.yaml` shows the exact `workflow_dispatch` payload to
trigger `.github/workflows/ml-pipeline.yml` for your model. The pipeline:

1. Calls `POST /api/v1/dags/train_domain_adapter/dagRuns`
   with `conf.model_id = {{MODEL_NAME}}`, `conf.tenant = {{TENANT}}`,
   `conf.domain = {{DOMAIN}}`
2. Polls `eval_adapter_debate` dag run until terminal state
3. Reads eval metrics from MLflow — gate: `win_rate >= 0.55`
4. Registers model version in MLflow and transitions to Staging
5. Generates SBOM (`.github/actions/syft-sbom`) and cosign-signs the artifact
6. Opens Kargo promotion: dev (auto) → staging (reviewer) → prod (manual gate)

No changes to the workflow file are needed — it is parameterised by `inputs.model`.

Reference: `.github/workflows/ml-pipeline.yml`

---

## Step 3 — Configure drift monitoring (WS-C)

Apply the substituted `values-ml-monitoring.yaml` as a per-model override. Options:

- **Recommended:** add a `modelNamespaces` entry in the main
  `apps/infra/ml-monitoring/values.yaml` PR.
- **Alternative:** create a standalone ArgoCD Application that merges
  `apps/infra/ml-monitoring/values.yaml` with your per-model overrides.

The WS-C chart deploys per namespace:
- An Evidently `drift-exporter` Deployment (accuracy, PSI, KL divergence, F1)
- A whylogs profiler Deployment (inline distribution profiling)
- A ServiceMonitor so Prometheus scrapes `/metrics` on port 8001
- A PrometheusRule with `{{TEAM_SLUG_UPPER}}_DRIFT_HIGH` and
  `{{TEAM_SLUG_UPPER}}_ACCURACY_LOW` alert groups (TEAM_SLUG_UPPER = upper-case
  version of TEAM_SLUG with hyphens replaced by underscores)

The drift alert fires the retrain trigger webhook:
`POST $AIRFLOW_BASE_URL/api/v1/dags/train_domain_adapter/dagRuns`
with `conf = {"tenant": "{{TENANT}}", "domain": "{{DOMAIN}}", "trigger_reason": "drift"}`.

Reference: `apps/infra/ml-monitoring/values.yaml`,
`docs/adrs/0038-ml-observability-drift.md`

---

## Step 4 — Provision team dashboard (WS-D)

Create a PR adding your substituted files:

```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/argocd-application.yaml
```

The WS-D chart provisions:
- A Grafana folder `team-{{TEAM_SLUG}}`
- A starter dashboard with RED metrics, resource saturation, alerts table, and ML panels
  (ML panels activate because `ml.enabled: true` — drift score, accuracy, retrain trigger
  rate, all scoped to `model_name = {{MODEL_NAME}}`, `tenant = {{TENANT}}`)
- A PrometheusRule with availability + saturation + ML alert groups
  in namespace `{{MODEL_NAMESPACE}}`

Reference: `apps/infra/grafana-self-serve/values.yaml`,
`docs/self-serve-observability.md`, `docs/adrs/0039-self-serve-observability.md`

---

## Step 5 — Contract sign-off

Before merging the ArgoCD Application into staging, confirm:

```
[ ] docs/contracts/model-api-contract.md read by all four personas
[ ] Request/response schema for {{MODEL_NAME}} matches the contract spec
[ ] Feature schema for {{MODEL_NAME}} matches the contract spec
[ ] Signed off by:
    Data Eng lead _________
    ML Eng lead _________
    Backend lead _________
    Frontend lead _________  (if a UI consumes this model)
```

See `docs/contracts/example-domain-adapter-contract.yaml` for a worked example.

---

## Step 6 — Open the PR

PR checklist:
- [ ] All `{{PLACEHOLDER}}` substituted; no raw template strings remain in output files
- [ ] `yamllint -c .yamllint.yml` passes on all new YAML files
- [ ] `helm template apps/infra/grafana-self-serve \
       -f apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml`
       renders without error
- [ ] ADR-0028 labels present on every K8s resource:
      `platform.system`, `platform.owner`, `platform.env`,
      `platform.component`, `platform.managed-by`
- [ ] Contract sign-off documented in PR description
- [ ] Link to the MLflow experiment URL once first training run completes

---

## Platform support

Questions? Contact `#platform-eng` on Slack or open an issue referencing:
- ADR-0037 (WS-B): training pipeline issues
- ADR-0038 (WS-C): drift monitoring issues
- ADR-0039 (WS-D): dashboard issues
- ADR-0041 (WS-F): this template

---

## Backstage future mapping

When ADR-0034 is revisited, this template maps to a Backstage Software Template:

```yaml
# catalog-info.yaml (future — do not deploy before ADR-0034 revisit)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: new-model-service
spec:
  type: model-service
  parameters:
    - title: Model identity
      properties:
        modelName:       # -> {{MODEL_NAME}}
        namespace:       # -> {{MODEL_NAMESPACE}}
        tenant:          # -> {{TENANT}}
        domain:          # -> {{DOMAIN}}
    - title: Team identity
      properties:
        teamSlug:        # -> {{TEAM_SLUG}}
        teamName:        # -> {{TEAM_NAME}}
        teamOwner:       # -> {{TEAM_OWNER}}
        platformEnv:     # -> {{PLATFORM_ENV}}
  steps:
    - id: fetch-template
      action: fetch:template
      input:
        url: ./templates/golden-paths/new-model-service
    - id: publish
      action: publish:github:pull-request
    - id: register
      action: catalog:register
```
