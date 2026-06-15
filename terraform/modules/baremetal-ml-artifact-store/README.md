# baremetal-ml-artifact-store

**ADRs cited:** ADR-0037 (orchestrator/registry), ADR-0049 (UK isolated control plane), ADR-0052 (Rook-Ceph/MinIO storage substrate)

**WS-B — ML CI/CD pipelines + model registry (bare metal)**

Bare-metal analogue of `ml-artifact-store` (GCS/Workload Identity). Provisions:

- Kubernetes `Namespace` and `ServiceAccount` for MLflow (gated by `var.enabled`).
- ESO `ExternalSecret` materialising scoped S3 credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `MLFLOW_S3_ENDPOINT_URL`) from Vault KV v2 (path `var.vault_path`) into a `Secret` consumed by MLflow and the GH Actions `ml-pipeline-baremetal.yml`.
- Optional MinIO Operator Helm release (`var.minio_deploy_in_cluster = true`) for the ML artifact store bucket. Defaults to connecting to the pre-existing UK-DC MinIO pools (already listed in `docs/transaction-analytics/06-uk-datacenters.md`).

## Storage substrate decision (ADR-0052 §7 OPEN DECISION 4)

| Option | When to use | S3 endpoint |
|--------|------------|-------------|
| `minio` (default) | MinIO pools already exist in the UK DC | `http://minio.minio-system.svc.cluster.local:9000` |
| `ceph-rgw` | Rook-Ceph RGW is deployed (ADR-0052); one fewer system | `http://rook-ceph-rgw-my-store.rook-ceph.svc.cluster.local:80` |

Switch by setting `var.backend`. MLflow and GH Actions use the S3-compatible API in both cases — no code change needed.

## ADR-0028 labels

All resources carry `platform.system = ml-pipeline`, `platform.component = model-registry`, `platform.managed-by = terragrunt` plus caller-supplied `platform.env` and `platform.owner`.

## Apply-gated

`var.enabled` defaults to `false`. No resource is created during plan-only runs. Set `enabled = true` only after explicit human review.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `enabled` | `bool` | `false` | Master gate (apply-gated) |
| `backend` | `string` | `"minio"` | `"minio"` or `"ceph-rgw"` |
| `s3_endpoint_url` | `string` | MinIO in-cluster | S3-compatible endpoint (no credentials) |
| `bucket_name` | `string` | `"mlflow-artifacts"` | Bucket name |
| `vault_path` | `string` | `secret/data/ml-pipeline/mlflow-s3-credentials` | Vault KV v2 path |
| `cluster_secret_store_name` | `string` | `"vault-cluster-store"` | ESO ClusterSecretStore name |
| `namespace` | `string` | `"ml-pipeline"` | K8s namespace |
| `kubernetes_service_account` | `string` | `"mlflow"` | K8s SA name |
| `minio_deploy_in_cluster` | `bool` | `false` | Deploy MinIO Operator Helm chart in-cluster |
| `platform_labels` | `map(string)` | staging/team-ml | ADR-0028 caller labels |

## Outputs

| Name | Description |
|------|-------------|
| `namespace` | K8s namespace name |
| `secret_name` | ESO-created Secret name with S3 credentials |
| `s3_endpoint_url` | S3 endpoint URL (for downstream wiring) |
| `bucket_name` | Bucket name |
| `backend` | Backend in use |
| `mlflow_service_account` | K8s SA name |
| `platform_labels` | Merged ADR-0028 labels |
