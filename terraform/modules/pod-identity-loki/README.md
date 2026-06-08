# pod-identity-loki

EKS **Pod Identity** for **Loki** (S3 object storage) — part of the observability
step in the [ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
cutover (YACE → **observability stack** → ESO → LB controller). Replaces Loki's
IRSA `loki-s3-access` role.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Loki role. **Trust targets `pods.eks.amazonaws.com`** (not an OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. |
| `aws_iam_policy.loki_s3` | S3 list + object CRUD scoped to Loki's bucket ARNs, plus KMS decrypt/data-key for SSE-KMS buckets. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.loki_s3` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=observability, service_account=loki)` → the role. **Replaces the IRSA annotation.** |

## Coexistence & caveats

- **Never put both on one SA.** The Loki SA drops its `eks.amazonaws.com/role-arn`
  annotation (`apps/infra/observability/loki-stack/templates/loki-s3-secret.yaml`)
  once this association exists.
- **Least-privilege:** pass `bucket_names` (and `kms_key_arns` for SSE-KMS) — the
  default `*` is for plan-time convenience only.
- **Fargate unsupported.** Verify Loki pods are not Fargate-scheduled.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster | `string` | — | **yes** |
| `namespace` | Loki namespace | `string` | `"observability"` | no |
| `service_account` | Loki SA | `string` | `"loki"` | no |
| `bucket_names` | Loki S3 bucket names | `list(string)` | `[]` (→ `*`) | no |
| `kms_key_arns` | SSE-KMS CMK ARNs | `list(string)` | `[]` (→ `*`) | no |
| `aws_partition` | ARN partition | `string` | `"aws"` | no |
| `iam_path` | IAM path | `string` | `"/pod-identity/"` | no |
| `max_session_duration` | Role max session seconds | `number` | `3600` | no |
| `tags` | Extra tags | `map(string)` | `{}` | no |

## Outputs

`role_arn`, `role_name`, `policy_arn`, `association_id`, `association_arn`.

## References

- ADR-0018 — EKS Pod Identity as default workload identity
- [Pod Identity ABAC session tags](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html)
