# AWS ML Model API Contract -- AWS-specific addendum

**Version:** 1.0.0
**Status:** Ratified -- AWS-specific addendum to `docs/contracts/model-api-contract.md`
**Platform:** AWS EKS GPU ML cluster (ADR-0044 / ADR-0048)
**ADR gates:** ADR-0041 (WS-F contracts), ADR-0048 (AWS backends)

This document is an **addendum** to the base contract at
`docs/contracts/model-api-contract.md`. It records the AWS-specific backend
and identity wiring that all four personas must understand before a model
service is promoted beyond staging on the AWS EKS ML cluster.

Read `docs/contracts/model-api-contract.md` first. This document adds AWS
specifics only; it does not duplicate the request/response schema, versioning
policy, or feature schema sections.

All four engineering personas (Data Engineering, ML Engineering, Backend/Frontend,
Platform/SRE) must sign off on a new model's contract instance (base + this
addendum) before staging promotion. See
`docs/golden-paths/aws-ml-RACI-and-handoffs.md` for the sign-off checklist.

---

## 1. AWS backend wiring (ADR-0048)

### 1.1 Artifact store (S3)

Model artifacts are stored in S3, not GCS:

```
s3://mlflow-artifacts-{env}-{account_id}/{model_name}/{tenant}/{domain}/{run_id}/artifacts/
```

**Access pattern:**

- MLflow tracking-server ServiceAccount has a Pod Identity binding to the
  `aws-ml-artifact-store` IAM role (ADR-0018, ADR-0048 D2).
- The IAM role policy includes the ABAC condition:

```json
{
  "Condition": {
    "StringEquals": {
      "aws:PrincipalTag/platform:system": "${aws:ResourceTag/platform:system}"
    }
  }
}
```

  Value `ml-pipeline` on both the principal tag and the bucket tag.
  Cross-system access is denied.
- No static AWS credentials are used anywhere in the ML stack (ADR-0018).

**New-model checklist:**

- [ ] S3 bucket exists with tag `platform:system = ml-pipeline`
- [ ] `aws-ml-artifact-store` IAM role ARN is documented in the model's ArgoCD
  Application annotation (`platform.aws/drift-exporter-pod-identity-role`)
- [ ] MLflow experiment confirms artifacts written to `s3://` (not `gs://`)

### 1.2 MLflow backend (RDS Postgres)

- MLflow metadata (experiments, runs, metrics, tags) stored in a **dedicated
  RDS PostgreSQL** instance (Multi-AZ, DBA-owned; ADR-0048 D3).
- Credentials delivered via **ESO ExternalSecret** from **AWS Secrets Manager**
  (ADR-0008 + rotation ADR-0031). No static DB passwords in-cluster.
- Connection string injected as `MLFLOW_TRACKING_URI` env var into the MLflow pod.

**New-model checklist:**

- [ ] MLflow tracking server is reachable (`curl $MLFLOW_TRACKING_URI/health`)
- [ ] ESO ExternalSecret status is `Ready` in the `mlflow` namespace
- [ ] `MLFLOW_TRACKING_URI` resolves to the RDS-backed server (not a GCP Cloud SQL)

### 1.3 Container registry (ECR)

Model images are stored in ECR with the existing pull-through cache (ADR-0029):

```
{account_id}.dkr.ecr.{region}.amazonaws.com/{model_name}:{env}-{commit_sha}
```

- Images are **cosign-signed** and **SBOM'd with syft** (`.github/actions/*` composites)
  before push; Kyverno admission verifies the signature.
- Upstream base images (NVIDIA NGC, Python) come through the pull-through cache --
  no direct pulls from upstream registries in the cluster.

**New-model checklist:**

- [ ] ECR repository `{account_id}.dkr.ecr.{region}.amazonaws.com/{model_name}` exists
- [ ] Pipeline run confirms cosign signature and SBOM attached to the pushed digest
- [ ] MLflow run metadata records the ECR image URI

---

## 2. Identity and ABAC (ADR-0018, ADR-0028)

Every pod that reads or writes cloud resources on behalf of a model must use
**EKS Pod Identity** -- no static credentials (ADR-0018). The Pod Identity binding
is documented in the model's ArgoCD Application annotation.

The ABAC condition is enforced on every IAM policy for S3 and Secrets Manager
resources related to ML workloads. A pod tagged `platform:system = ml-pipeline`
can only access resources also tagged `platform:system = ml-pipeline`.

**New-model checklist:**

- [ ] Model pod ServiceAccount has a Pod Identity association to the correct IAM role
- [ ] IAM role trust policy restricts to the specific ServiceAccount + namespace
- [ ] S3 bucket, IAM role, and ECR repository carry all five ADR-0028 tags:
  `platform:system`, `platform:component`, `platform:env`, `platform:owner`,
  `platform:managed-by`

---

## 3. Drift monitoring (WS-C, AWS)

The Evidently drift-exporter reads the model's reference dataset from S3 (not GCS):

```
s3://{mlflow_artifacts_bucket}/{model_name}/{tenant}/{domain}/reference.parquet
```

Access is via a separate Pod Identity binding for the `drift-exporter` ServiceAccount
(same ABAC pattern; role scoped to the reference-dataset prefix only).

The Prometheus Pushgateway address and the retrain-trigger webhook to Airflow REST
are **cluster-agnostic** -- identical to the GCP etalon (ADR-0048 D4).

**New-model checklist:**

- [ ] Reference dataset uploaded to the S3 path above before first drift-monitor run
- [ ] Drift-exporter ServiceAccount has Pod Identity binding with `s3:GetObject`
  on the reference-dataset prefix
- [ ] `ServiceMonitor` is scraped by Prometheus (verify in Prometheus targets UI)
- [ ] PrometheusRule alerts visible in Alertmanager

---

## 4. Worked example (AWS)

See `docs/contracts/example-domain-adapter-contract.yaml` for the domain-adapter
model instance. For the AWS deployment, substitute:

| GCP field | AWS equivalent |
|-----------|----------------|
| `artifactStore.uri: gs://...` | `artifactStore.uri: s3://mlflow-artifacts-prod-{account_id}/...` |
| `identity: workload-identity` | `identity: pod-identity` |
| `identityRef: {gsa}@{project}.iam.gserviceaccount.com` | `identityRef: arn:aws:iam::{account_id}:role/aws-ml-artifact-store` |
| `registry: gcr.io/{project}/{model}` | `registry: {account_id}.dkr.ecr.{region}.amazonaws.com/{model}` |
| `backend.type: cloud-sql` | `backend.type: rds-postgres` |
| `backend.connectionString: cloudsql://...` | `backend.connectionString` from ESO ExternalSecret |

---

## 5. Versioning alignment

This addendum follows the same semver policy as the base contract
(`docs/contracts/model-api-contract.md`). Breaking changes to the AWS backend
wiring (e.g., changing the ABAC condition pattern, replacing the artifact bucket
naming scheme, or switching identity mechanism) increment `MAJOR` and require a
new sign-off from all four personas.

---

## References

- Base contract: `docs/contracts/model-api-contract.md`
- Example: `docs/contracts/example-domain-adapter-contract.yaml`
- RACI (AWS): `docs/golden-paths/aws-ml-RACI-and-handoffs.md`
- ADR-0048: AWS ML CI/CD + MLflow backends (S3, RDS, ECR)
- ADR-0041: golden-path templates + contracts (WS-F)
- ADR-0028: platform taxonomy tags + ABAC
- ADR-0018: EKS Pod Identity
- ADR-0008: External Secrets Operator + rotation ADR-0031
- ADR-0029: ECR pull-through cache
- ADR-0038: ML drift monitoring (retrain trigger, WS-C)

---

*AWS-specific addendum to the base model API contract.
Planning-only -- ratified alongside the WS-F golden-path templates (ADR-0041).
Implementation apply-gated; no cloud resources are created by this document.*
