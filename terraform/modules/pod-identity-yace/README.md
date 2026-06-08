# pod-identity-yace

EKS **Pod Identity** for the **YACE** CloudWatch exporter — the first workload in
the [ADR-0018](../../../docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md)
cutover from IRSA to Pod Identity. YACE is the safest canary: CloudWatch
read-only, a single ServiceAccount, no ingress dependency.

## What it creates

| Resource | Purpose |
|---|---|
| `aws_iam_role.this` | Workload role. **Trust policy targets the EKS Auth service principal `pods.eks.amazonaws.com`** (not a per-cluster OIDC issuer), allowing **`sts:AssumeRole` + `sts:TagSession`**. `TagSession` is required so EKS can inject the ABAC session tags. |
| `aws_iam_policy.cloudwatch_read` | CloudWatch metrics + Resource-Groups-Tagging read, plus the Describe/List calls YACE needs to resolve dimensions. **ABAC-scoped** by `aws:PrincipalTag/kubernetes-namespace`. |
| `aws_iam_role_policy_attachment.cloudwatch_read` | Attaches the policy. |
| `aws_eks_pod_identity_association.this` | Binds `(cluster, namespace=observability, service_account=yace)` → the role. **This replaces the IRSA `eks.amazonaws.com/role-arn` annotation.** |

## Pod Identity vs IRSA (why this differs from the old role)

- **No OIDC issuer in the trust policy.** IRSA bakes a cluster's OIDC issuer URL
  into the role's trust, making the role non-portable. Pod Identity trusts the
  EKS service principal, so **one role is reusable across clusters**.
- **Least-privilege via ABAC, not role-per-workload.** EKS injects six session
  tags on every pod credential vend:
  `eks-cluster-arn`, `eks-cluster-name`, `kubernetes-namespace`,
  `kubernetes-service-account`, `kubernetes-pod-name`, `kubernetes-pod-uid`.
  Policies condition on `aws:PrincipalTag/<key>`. This module demonstrates the
  pattern by scoping every statement to
  `aws:PrincipalTag/kubernetes-namespace == observability`; `main.tf` includes a
  commented fuller example pinning the ServiceAccount and cluster too.

## Coexistence & cutover (ADR-0018)

- **IRSA stays supported** for workloads not yet migrated. Pod Identity and IRSA
  coexist at the cluster level during the migration window.
- **Never put both on one ServiceAccount.** AWS leaves the precedence when a
  single SA carries *both* an IRSA annotation *and* a Pod Identity association
  **undocumented**. We therefore treat "both" as unsupported and **drop the IRSA
  annotation as the final per-workload migration step**. For YACE this means
  removing `eks.amazonaws.com/role-arn` from
  `apps/infra/observability/yace/values.yaml` (done in this change) once the
  association exists.
- **OIDC provider / `enable_irsa`** can be dropped from a cluster only after *all*
  its workloads are migrated — not in this change (YACE is first of several).

## Caveats

- **Fargate is unsupported.** The Pod Identity agent is a node-level DaemonSet;
  Fargate has no node to run it. Any Fargate-scheduled workload must stay on IRSA.
  YACE here runs on Graviton EC2/Karpenter nodes, so it is eligible.
- **Karpenter nodes** must run the agent DaemonSet before cutover — verify the
  node images / DaemonSet land on new nodes.
- **Prerequisite:** the `eks-pod-identity-agent` EKS addon must be installed on
  the cluster (assumed per ADR-0018).

## Usage

Via the catalog unit (`catalog/units/pod-identity-yace/terragrunt.hcl`):

```hcl
inputs = {
  project         = "platform-design"
  cluster_name    = "platform-dev"   # the EKS cluster running YACE
  namespace       = "observability"
  service_account = "yace"
}
```

Or directly:

```hcl
module "pod_identity_yace" {
  source = "../../terraform/modules/pod-identity-yace"

  cluster_name = "platform-dev"
  # namespace / service_account default to observability / yace
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project` | Naming prefix for the role/policy | `string` | `"platform-design"` | no |
| `cluster_name` | EKS cluster the association is created on | `string` | — | **yes** |
| `namespace` | YACE namespace (drives the ABAC condition) | `string` | `"observability"` | no |
| `service_account` | YACE ServiceAccount name | `string` | `"yace"` | no |
| `iam_path` | IAM path for the role/policy | `string` | `"/pod-identity/"` | no |
| `max_session_duration` | IAM role max session seconds | `number` | `3600` | no |
| `tags` | Extra tags merged onto all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | YACE Pod Identity role ARN |
| `role_name` | YACE Pod Identity role name |
| `policy_arn` | ABAC-scoped CloudWatch read policy ARN |
| `association_id` | Pod Identity association ID |
| `association_arn` | Pod Identity association ARN |

## References

- ADR-0018 — EKS Pod Identity as default workload identity
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [Pod Identity ABAC session tags](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html)
