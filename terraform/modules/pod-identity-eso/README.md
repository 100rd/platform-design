# pod-identity-eso

EKS **Pod Identity** for the **External Secrets Operator (ESO)** controller — part
of the [ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
cutover from IRSA to Pod Identity (cutover order: YACE → observability stack →
**ESO** → LB controller).

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Controller role. **Trust targets `pods.eks.amazonaws.com`** (not an OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. |
| `aws_iam_policy.eso` | SecretsManager read + PushSecret write, KMS decrypt/data-key for the secrets CMK, and `ecr:GetAuthorizationToken` for the `ECRAuthorizationToken` generator. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.eso` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=external-secrets, service_account=external-secrets)` → the role. **Replaces the IRSA annotation.** |

## ESO specifics (ADR-0018)

- **ESO uses its OWN controller SA identity, not `serviceAccountRef`.** With Pod
  Identity the agent injects credentials into the ESO controller pod directly.
- **Generators adopted (no Vault):** `ECRAuthorizationToken` (short-lived ECR pull
  creds) and `Password` → `PushSecret` (writes credentials into Secrets Manager).
  Hence SecretsManager read+write, KMS, and ECR auth-token in one policy.
- **Prerequisite:** upgrade ESO `0.10.5 → v2.6.0` (CRDs move to `v1`) before
  migrating ESO onto Pod Identity.

## Coexistence & caveats

- **Never put both on one SA.** Drop `eks.amazonaws.com/role-arn` from the ESO
  controller SA once this association exists.
- **Fargate unsupported.** Verify the controller is not Fargate-scheduled.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster | `string` | — | **yes** |
| `namespace` | ESO namespace | `string` | `"external-secrets"` | no |
| `service_account` | ESO controller SA | `string` | `"external-secrets"` | no |
| `secret_arn_patterns` | SecretsManager ARN scope | `list(string)` | `[]` (→ `*`) | no |
| `kms_key_arns` | Secrets CMK ARNs | `list(string)` | `[]` (→ `*`) | no |
| `iam_path` | IAM path | `string` | `"/pod-identity/"` | no |
| `max_session_duration` | Role max session seconds | `number` | `3600` | no |
| `tags` | Extra tags | `map(string)` | `{}` | no |

## Outputs

`role_arn`, `role_name`, `policy_arn`, `association_id`, `association_arn`.

## References

- ADR-0018 — EKS Pod Identity as default workload identity
- [Pod Identity ABAC session tags](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html)
- [ESO Generators / PushSecret](https://external-secrets.io/latest/api/generator/)
