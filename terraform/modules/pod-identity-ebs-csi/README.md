# pod-identity-ebs-csi

EKS **Pod Identity** for the **EBS CSI driver** controller — part of the
[ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
rollout from IRSA to Pod Identity. The driver provisions/attaches/snapshots EBS
volumes for PersistentVolumeClaims.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Controller role. **Trust targets `pods.eks.amazonaws.com`** (not an OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. |
| `aws_iam_policy.ebs_csi` | EC2 volume lifecycle (create/attach/detach/delete/modify), snapshot lifecycle, describe, tagging, plus KMS grants for CMK-encrypted volumes. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.ebs_csi` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=kube-system, service_account=ebs-csi-controller-sa)` → the role. **Replaces the IRSA annotation / addon role.** |

## Coexistence & caveats

- **Never put both on one SA.** Drop the IRSA role from the EBS CSI controller SA
  once this association exists. If the driver is an EKS managed addon, remove the
  addon's `service_account_role_arn`.
- **Least-privilege:** pass `kms_key_arns` to scope CMK-encrypted-volume grants —
  the default `*` is for plan-time convenience only.
- **Fargate unsupported** (and EBS volumes are not attachable to Fargate pods); the
  controller runs on EC2/Karpenter nodes.
- **Prerequisite:** `eks-pod-identity-agent` addon installed on the cluster.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster | `string` | — | **yes** |
| `namespace` | Controller namespace | `string` | `"kube-system"` | no |
| `service_account` | Controller SA | `string` | `"ebs-csi-controller-sa"` | no |
| `kms_key_arns` | Volume-encryption CMK ARNs | `list(string)` | `[]` (→ `*`) | no |
| `iam_path` | IAM path | `string` | `"/pod-identity/"` | no |
| `max_session_duration` | Role max session seconds | `number` | `3600` | no |
| `tags` | Extra tags | `map(string)` | `{}` | no |

## Outputs

`role_arn`, `role_name`, `policy_arn`, `association_id`, `association_arn`.

## References

- ADR-0018 — EKS Pod Identity as default workload identity
- [Pod Identity ABAC session tags](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html)
- [AmazonEBSCSIDriverPolicy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEBSCSIDriverPolicy.html)
