# pod-identity-thanos

EKS **Pod Identity** for **Thanos** (S3 object storage) — part of the observability
step in the [ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
cutover (YACE → **observability stack** → ESO → LB controller). Replaces Thanos's
IRSA `thanos-s3-access` role.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Thanos role. **Trust targets `pods.eks.amazonaws.com`** (not an OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. |
| `aws_iam_policy.thanos_s3` | S3 list + object CRUD scoped to Thanos's bucket ARNs, plus KMS decrypt/data-key for SSE-KMS buckets. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.thanos_s3` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=monitoring, service_account=thanos)` → the role. **Replaces the IRSA annotation.** |

## Coexistence & caveats

- **Never put both on one SA.** The Thanos SA (kube-prometheus-stack template)
  drops its `eks.amazonaws.com/role-arn` annotation once this association exists.
  > NOTE: the Thanos SA template lives inside `apps/infra/observability/prometheus-stack/`,
  > which is out of scope for the change that introduced this module; the
  > annotation drop there is tracked separately. This module + unit provide the
  > Pod Identity side so the SA can be migrated when prometheus-stack is touched.
- **Least-privilege:** pass `bucket_names` (and `kms_key_arns` for SSE-KMS) — the
  default `*` is for plan-time convenience only.
- **Fargate unsupported.** Verify Thanos pods are not Fargate-scheduled.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster | `string` | — | **yes** |
| `namespace` | Thanos namespace | `string` | `"monitoring"` | no |
| `service_account` | Thanos SA | `string` | `"thanos"` | no |
| `bucket_names` | Thanos S3 bucket names | `list(string)` | `[]` (→ `*`) | no |
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
