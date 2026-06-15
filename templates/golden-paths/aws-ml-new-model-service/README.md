# Golden Path: AWS ML — New Model Service

> **Platform:** AWS EKS GPU ML cluster (ADR-0044 / ADR-0048)
> **ADR gates:** ADR-0041 (template approach), ADR-0048 (AWS backends)
> **GCP etalon:** `templates/golden-paths/new-model-service/` (GCP/GKE variant)
>
> This is the **AWS-flavoured** golden path. The ML logic (Airflow DAG corpus,
> MLflow train→eval→gate→register→deploy, Evidently drift, retrain trigger) is
> **identical** to the GCP etalon (inherited from ADR-0037/0038 via ADR-0048).
> Only the cloud-specific wiring differs: S3 artifact store + EKS Pod Identity/ABAC
> (not GCS + Workload Identity), ECR (not GCR), RDS Postgres (not Cloud SQL),
> AWS Secrets Manager + ESO (not GCP Secret Manager).

This template wires a new ML model into the full AWS ML platform stack:

- **WS-B** (ADR-0048 <- ADR-0037): `ml-pipeline.yml` train->eval->register->deploy
  with MLflow on S3 + RDS backends (EKS Pod Identity/ABAC)
- **WS-C** (ADR-0048 <- ADR-0038): Evidently drift-exporter + whylogs profiler
  per-model namespace, Prometheus->Alertmanager->PagerDuty
- **WS-D** (ADR-0039): `grafana-self-serve` per-team dashboard + alert rules

Backstage scaffolder mapping: `spec.type: model-service`
(see "Backstage future mapping" below; ADR-0034 remains deferred).

Chart versions verified against:

- `apps/infra/ml-monitoring` (WS-C) as of 2026-06-15
- `apps/infra/grafana-self-serve` (WS-D) as of 2026-06-15
- `.github/workflows/ml-pipeline.yml` (WS-B) as of 2026-06-15
- `apps/infra/mlflow` (S3/RDS backend) as of 2026-06-15

---

## Prerequisites

Before you start, confirm:

- [ ] Namespace `{{MODEL_NAMESPACE}}` exists on the `aws-eks-gpu-*` ML cluster
  (or ask Platform: `kubectl create namespace {{MODEL_NAMESPACE}}`)
- [ ] S3 bucket `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}` exists and carries
  `platform:system = ml-pipeline` tag (provisioned by WS-B
  `terraform/modules/aws-ml-artifact-store` + `catalog/units/aws-ml-artifact-store`)
- [ ] The `aws-ml-artifact-store` IAM role ARN is known
  (`aws_ml_artifact_store_role_arn` output of the catalog unit)
- [ ] MLflow tracking server is reachable at `$MLFLOW_TRACKING_URI`
  (deployed by WS-B `apps/infra/mlflow/`)
- [ ] Airflow is reachable at `$AIRFLOW_BASE_URL`
  (deployed by WS-B `apps/infra/airflow/`)
- [ ] Grafana service account `grafana-sa-{{TEAM_SLUG}}` exists in Grafana
  (create via Grafana UI or API before ArgoCD sync)
- [ ] Model training code lives under `models/{{MODEL_NAME}}/` or
  `adapters/{{MODEL_NAME}}/` (triggers `.github/workflows/ml-pipeline.yml` on push)
- [ ] You have read `docs/contracts/model-api-contract.md` and
  `docs/contracts/aws-ml-model-api-contract.md` and your model's schema matches
- [ ] Contract sign-off obtained from Data Eng, Backend, and Frontend leads
  (see `docs/golden-paths/aws-ml-RACI-and-handoffs.md` -- required before staging)
- [ ] ECR repository exists at
  `{{AWS_ACCOUNT_ID}}.dkr.ecr.{{AWS_REGION}}.amazonaws.com/{{MODEL_NAME}}`
  (ECR pull-through cache covers upstream bases per ADR-0029)

---

## Step 1 -- Substitute placeholders

Copy this template directory to a working location and substitute all
`{{UPPER_SNAKE_CASE}}` placeholders. Use `envsubst` or `sed`:

```bash
# AWS-specific
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"
export S3_MLFLOW_ARTIFACTS_BUCKET="mlflow-artifacts-prod-${AWS_ACCOUNT_ID}"
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Model identity
export MODEL_NAME="fraud-uk"
export MODEL_NAMESPACE="fraud-uk"
export TEAM_SLUG="team-ml-fraud"
export TEAM_NAME="ML Fraud"
export TEAM_OWNER="team-ml-fraud"
export TENANT="tenant-acme"
export DOMAIN="hft"               # one of: hft, solana, insurance, rtb
export PLATFORM_ENV="production"  # production | staging | dev | sandbox

# Substitute all template files
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

## Step 2 -- Wire the training pipeline (WS-B, AWS)

The file `ml-pipeline-trigger.yaml` shows the `workflow_dispatch` payload to
trigger `.github/workflows/ml-pipeline.yml` for your model. On AWS the pipeline:

1. Calls `POST /api/v1/dags/train_domain_adapter/dagRuns`
   with `conf.model_id = {{MODEL_NAME}}`, `conf.tenant = {{TENANT}}`,
   `conf.domain = {{DOMAIN}}`
2. Polls `eval_adapter_debate` DAG run until terminal state
3. Reads eval metrics from MLflow (RDS Postgres backend, creds via ESO);
   gate: `win_rate >= 0.55`
4. Registers model version in MLflow; artifact written to
   `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/{{MODEL_NAME}}/{{TENANT}}/{{DOMAIN}}/`
   via EKS Pod Identity + ABAC (IAM condition:
   `aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`)
5. Generates SBOM (`.github/actions/syft-sbom`) and cosign-signs the artifact
6. Pushes the model image to ECR:
   `{{ECR_REGISTRY}}/{{MODEL_NAME}}:{{PLATFORM_ENV}}-<commit-sha>`
7. Opens Kargo promotion: dev (auto) -> staging (reviewer) -> prod (manual gate)

No changes to the workflow file are needed -- it is parameterised by `inputs.model`.

**AWS delta vs GCP etalon:**
- Artifact store: S3 (not GCS); identity: EKS Pod Identity + ABAC (not GKE WI + GSA)
- Registry: ECR with pull-through cache (not GCR)
- Secrets: AWS Secrets Manager + ESO (not GCP Secret Manager)

Reference: `.github/workflows/ml-pipeline.yml`, ADR-0048 D1/D2/D5

---

## Step 3 -- Configure drift monitoring (WS-C)

Apply the substituted `values-ml-monitoring.yaml` as a per-model override:

- **Recommended:** add a `modelNamespaces` entry in the main
  `apps/infra/ml-monitoring/values.yaml` PR.
- **Alternative:** create a standalone ArgoCD Application that merges
  `apps/infra/ml-monitoring/values.yaml` with your per-model overrides.

The WS-C chart deploys per namespace:

- An Evidently `drift-exporter` Deployment (accuracy, PSI, KL divergence, F1).
  Reads the reference dataset from
  `s3://{{S3_MLFLOW_ARTIFACTS_BUCKET}}/{{MODEL_NAME}}/{{TENANT}}/{{DOMAIN}}/reference.parquet`
  via the drift-exporter ServiceAccount's Pod Identity binding.
- A whylogs profiler Deployment (inline distribution profiling)
- A ServiceMonitor so Prometheus scrapes `/metrics` on port 8001
- A PrometheusRule with `{{TEAM_SLUG_UPPER}}_DRIFT_HIGH` and
  `{{TEAM_SLUG_UPPER}}_ACCURACY_LOW` alert groups
  (TEAM_SLUG_UPPER: upper-case TEAM_SLUG, hyphens replaced by underscores)

The drift alert fires the retrain trigger webhook -- cluster-agnostic (ADR-0048 D4):
`POST $AIRFLOW_BASE_URL/api/v1/dags/train_domain_adapter/dagRuns`
with `conf = {"tenant": "{{TENANT}}", "domain": "{{DOMAIN}}", "trigger_reason": "drift"}`.

Reference: `apps/infra/ml-monitoring/values.yaml`, ADR-0048 D4, ADR-0038

---

## Step 4 -- Provision team dashboard (WS-D)

Create a PR adding your substituted files:

```
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml
apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/argocd-application.yaml
```

The WS-D chart provisions (WS-D is cluster-agnostic -- identical to GCP):

- Grafana folder `team-{{TEAM_SLUG}}`
- Starter dashboard with RED metrics, resource saturation, alerts table, and ML panels
  (ML panels activate because `ml.enabled: true`; scoped to
  `model_name = {{MODEL_NAME}}`, `tenant = {{TENANT}}`)
- PrometheusRule with availability + saturation + ML alert groups
  in namespace `{{MODEL_NAMESPACE}}`

Reference: `apps/infra/grafana-self-serve/values.yaml`, ADR-0039

---

## Step 5 -- Contract sign-off

Before merging the ArgoCD Application into staging, confirm:

```
[ ] docs/contracts/model-api-contract.md read by all four personas
[ ] docs/contracts/aws-ml-model-api-contract.md AWS-specific section reviewed
[ ] Request/response schema for {{MODEL_NAME}} matches the contract spec
[ ] Feature schema for {{MODEL_NAME}} matches the contract spec
[ ] Signed off by:
    Data Eng lead   _________
    ML Eng lead     _________
    Backend lead    _________
    Frontend lead   _________  (if a UI consumes this model)
```

See `docs/contracts/example-domain-adapter-contract.yaml` for a worked example.
See `docs/golden-paths/aws-ml-RACI-and-handoffs.md` for the AWS RACI matrix.

---

## Step 6 -- Open the PR

PR checklist:

- [ ] All `{{PLACEHOLDER}}` substituted; no raw template strings remain in output files
- [ ] `yamllint -c .yamllint.yml` passes on all new YAML files
- [ ] `helm template apps/infra/grafana-self-serve \
       -f apps/infra/grafana-self-serve/example-teams/{{TEAM_SLUG}}/values.yaml`
       renders without error
- [ ] ADR-0028 tags present on every AWS resource (S3 bucket, IAM role, ECR repo):
      `platform:system`, `platform:owner`, `platform:env`,
      `platform:component`, `platform:managed-by`
- [ ] ADR-0028 labels present on every Kubernetes resource
- [ ] ABAC condition confirmed on S3 bucket IAM policy:
      `aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`
- [ ] Contract sign-off documented in PR description
- [ ] Link to MLflow experiment URL once first training run completes
- [ ] ECR image URI confirmed in MLflow run metadata

---

## AWS identity quick-reference

| Concern | How it is wired |
|---------|-----------------|
| MLflow -> S3 artifact store | EKS Pod Identity: `mlflow-sa` -> IAM role with `platform:system=ml-pipeline` ABAC condition |
| Drift exporter -> S3 ref dataset | EKS Pod Identity: `drift-exporter-sa` -> IAM role scoped to reference-dataset prefix |
| Airflow task pods | Run under Volcano scheduler (`schedulerName: volcano`); task SA has Pod Identity for task-specific S3 paths |
| RDS Postgres creds | ESO ExternalSecret from AWS Secrets Manager (ADR-0008 + rotation ADR-0031) |
| ECR pull | Pull-through cache (ADR-0029); node IAM role has `ecr:GetAuthorizationToken` |
| cosign signing | `.github/actions/cosign-sign` composite (inherited ADR-0037 D4) |
| SBOM generation | `.github/actions/syft-sbom` composite (inherited ADR-0037 D4) |

---

## Platform support

Contact `#platform-eng` on Slack or open an issue referencing:

- ADR-0044: EKS GPU cluster / scheduling / node issues
- ADR-0048: AWS ML pipeline, S3, RDS, ECR, drift wiring
- ADR-0041: this template (golden-path structure)
- ADR-0028: ADR-0028 tag / ABAC issues
- ADR-0018: EKS Pod Identity issues

---

## Backstage future mapping

When ADR-0034 is revisited, this template maps to a Backstage Software Template:

```yaml
# catalog-info.yaml (future -- do not deploy before ADR-0034 revisit)
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata:
  name: aws-ml-new-model-service
spec:
  type: model-service
  parameters:
    - title: AWS identity
      properties:
        awsAccountId:       # -> {{AWS_ACCOUNT_ID}}
        awsRegion:          # -> {{AWS_REGION}}
        s3ArtifactsBucket:  # -> {{S3_MLFLOW_ARTIFACTS_BUCKET}}
        ecrRegistry:        # -> {{ECR_REGISTRY}}
    - title: Model identity
      properties:
        modelName:          # -> {{MODEL_NAME}}
        namespace:          # -> {{MODEL_NAMESPACE}}
        tenant:             # -> {{TENANT}}
        domain:             # -> {{DOMAIN}}
    - title: Team identity
      properties:
        teamSlug:           # -> {{TEAM_SLUG}}
        teamName:           # -> {{TEAM_NAME}}
        teamOwner:          # -> {{TEAM_OWNER}}
        platformEnv:        # -> {{PLATFORM_ENV}}
  steps:
    - id: fetch-template
      action: fetch:template
      input:
        url: ./templates/golden-paths/aws-ml-new-model-service
    - id: publish
      action: publish:github:pull-request
    - id: register
      action: catalog:register
```
