# pod-identity-lb-controller

EKS **Pod Identity** for the **AWS Load Balancer Controller** — the last workload
in the [ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
cutover (YACE → observability stack → ESO → **LB controller**). Ingress-critical,
so migrated last.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Controller role. **Trust targets `pods.eks.amazonaws.com`** (not an OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. |
| `aws_iam_policy.lb_controller` | The LBC least-privilege policy: ELBv2 provisioning, EC2/VPC describe, managed-SG management, and WAFv2/Shield/ACM/Cognito read. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.lb_controller` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=kube-system, service_account=aws-load-balancer-controller)` → the role. **Replaces the IRSA annotation.** |

## Coexistence & caveats

- **Never put both on one SA.** Keep the LBC SA annotations empty
  (`apps/infra/aws-lb-controller/values.yaml`) — no `eks.amazonaws.com/role-arn`.
- **Fargate unsupported.** Verify the controller is not Fargate-scheduled.
- **Prerequisite:** `eks-pod-identity-agent` addon installed on the cluster.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster | `string` | — | **yes** |
| `namespace` | Controller namespace | `string` | `"kube-system"` | no |
| `service_account` | Controller SA | `string` | `"aws-load-balancer-controller"` | no |
| `iam_path` | IAM path | `string` | `"/pod-identity/"` | no |
| `max_session_duration` | Role max session seconds | `number` | `3600` | no |
| `tags` | Extra tags | `map(string)` | `{}` | no |

## Outputs

`role_arn`, `role_name`, `policy_arn`, `association_id`, `association_arn`.

## References

- ADR-0018 — EKS Pod Identity as default workload identity
- [Pod Identity ABAC session tags](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html)
- [AWS Load Balancer Controller IAM policy](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/)
