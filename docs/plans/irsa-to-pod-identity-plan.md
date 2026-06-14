# EKS Pod Identity Transition Plan (ADR-0018)

## 1. Executive Summary
This document outlines the detailed plan to transition EKS workload identities from **IRSA (IAM Roles for Service Accounts)** to **EKS Pod Identity** across the platform clusters. This transition is aligned with **ADR-0018** and aims to:
- Establish cluster-agnostic, portable IAM roles by trusting the EKS Auth service principal `pods.eks.amazonaws.com` rather than per-cluster OIDC identity providers.
- Implement attribute-based access control (ABAC) using EKS-injected session tags to enforce resource isolation at the namespace and service account levels.
- Reduce IAM role sprawl by collapsing duplicate roles across environments and clusters.
- Enable seamless cross-account resource access utilizing EKS Pod Identity's native support for `targetRoleArn` (GA 2025-06).

---

## 2. Core Controllers Analysis
We have analyzed the 6 core controllers currently deployed. Here is a summary of their current identity configuration, target Pod Identity parameters, and impact level:

| Controller | Legacy IRSA Role Pattern | Target Namespace | Target ServiceAccount | Pod Identity Module | Impact & Complexity |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **YACE** (CloudWatch Exporter) | `*-yace-cw-read` | `observability` | `yace` | `pod-identity-yace` | **Low** (Canary) — No state, non-critical metrics. |
| **Loki** (Log Storage) | `*-loki-s3-access` | `observability` | `loki` | `pod-identity-loki` | **Medium** — S3 backend access for logs. |
| **Thanos** (Metric Storage) | `*-thanos-s3-access` | `monitoring` | `thanos` | `pod-identity-thanos` | **Medium** — S3 backend access for historical metrics. |
| **External Secrets Operator** | `*-eso-secrets-manager` | `external-secrets` | `external-secrets` | `pod-identity-eso` | **High** — Requires ESO v2.6.0 Helm & CRD upgrade first. |
| **EBS CSI Driver** | EKS Managed Addon Role | `kube-system` | `ebs-csi-controller-sa` | `pod-identity-ebs-csi` | **High** — Critical storage provisioning; requires node-scheduling coordination. |
| **AWS Load Balancer Controller** | `*-aws-lb-controller` | `kube-system` | `aws-load-balancer-controller`| `pod-identity-lb-controller` | **Critical** — Handles all ingress traffic; must be migrated last. |

---

## 3. Prerequisite Steps
Before initiating any workload cutover, the following platform prerequisites must be completed:

### A. EKS Pod Identity Agent Addon Installation
Ensure the `eks-pod-identity-agent` EKS managed addon is active on all target clusters:
```bash
aws eks describe-addon --cluster-name <cluster-name> --addon-name eks-pod-identity-agent
```
If not installed, deploy it via the `eks-cluster` or `eks-addons` module:
```hcl
resource "aws_eks_addon" "pod_identity" {
  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}
```

### B. Karpenter Node Template Verification
Ensure that Karpenter node templates and launch configurations are configured to run the `eks-pod-identity-agent` DaemonSet. When new nodes join, they must automatically schedule the agent pod to ensure immediate identity availability.

### C. Fargate Workload Exclusion
EKS Pod Identity is **not** supported on AWS Fargate. If any controller or workload is scheduled to run on Fargate profiles, it **must** continue using IRSA. Ensure that the core controllers listed above are pinned to EC2/Karpenter node groups via node selectors or node affinities:
```yaml
nodeSelector:
  kubernetes.io/arch: amd64  # or arm64
```

---

## 4. Staging External Secrets Operator (ESO) Upgrade
Upgrading ESO from `0.10.5` to `v2.6.0` is a prerequisite for migrating ESO to Pod Identity. Because ESO v2.x graduates all Custom Resource Definitions (CRDs) to `v1` and removes `v1beta1`, the upgrade must follow a strict, staged migration procedure to prevent service disruption.

### Step-by-Step Upgrade Procedure:
1. **Apply Upgraded CRDs (Terraform)**:
   Navigate to the `platform-crds` Terragrunt unit and run:
   ```bash
   terragrunt run-all plan
   terragrunt run-all apply
   ```
   This registers the `external-secrets.io/v1` version alongside `v1beta1` in the API server.
2. **Migrate CR Manifests in Repo**:
   Update all `ExternalSecret`, `ClusterExternalSecret`, `SecretStore`, `ClusterSecretStore`, `PushSecret`, and Generator manifests in the repository to use `apiVersion: external-secrets.io/v1`:
   ```diff
   -apiVersion: external-secrets.io/v1beta1
   +apiVersion: external-secrets.io/v1
   ```
   *Note: Core fields remain backwards-compatible, so no field modifications are required.*
3. **CRD Storage Migration**:
   ESO v2 automatically triggers a storage migration on startup when the `--storage-version` flag is set (enabled by default). This writes all existing stored instances to the `v1` storage schema.
4. **Upgrade Helm Chart and Sync ArgoCD**:
   Bump the Helm chart dependency in `apps/infra/external-secrets/Chart.yaml` to `2.6.0` and appVersion to `v2.6.0`. Sync the application in ArgoCD:
   ```bash
   argocd app sync external-secrets
   ```
5. **Post-Upgrade Cleanup**:
   Once all resources are verified and operating on `v1`, remove the deprecated `v1beta1` served version from the `platform-crds` Terraform configuration.

---

## 5. IAM Trust Policies for EKS Pod Identity
Unlike IRSA, which requires trusting a specific OIDC Identity Provider (IdP) URL, EKS Pod Identity roles trust the EKS Auth service principal `pods.eks.amazonaws.com`.

### Trust Policy Document (Terraform HCL):
```hcl
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "EksPodIdentityAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}
```

> [!IMPORTANT]
> The `sts:TagSession` action is **mandatory**. Without it, EKS cannot append the session tags required for Attribute-Based Access Control (ABAC), and credential vending will fail.

---

## 6. ABAC Session Tag Policies for Resource Isolation
EKS Pod Identity injects six session tags (PrincipalTags) onto every vended credential session:
1. `eks-cluster-arn`
2. `eks-cluster-name`
3. `kubernetes-namespace`
4. `kubernetes-service-account`
5. `kubernetes-pod-name`
6. `kubernetes-pod-uid`

We leverage these tags to enforce strict, namespace-scoped least privilege. A single IAM role can be safely shared across environments/namespaces because its access is dynamically restricted to the invoking pod's namespace.

### Example: Namespace Isolation Policy (YACE CloudWatch Read)
```hcl
data "aws_iam_policy_document" "cloudwatch_read" {
  statement {
    sid       = "CloudWatchMetricsRead"
    effect    = "Allow"
    actions   = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/kubernetes-namespace"
      values   = [var.namespace] # Restricts metric retrieval to the yace controller's namespace
    }
  }
}
```

---

## 7. Migration and Coexistence Strategy
Because EKS Pod Identity and IRSA can run side-by-side on the same cluster, we must manage the coexistence carefully to avoid race conditions and undocumented behavior.

> [!CAUTION]
> **Do NOT configure both mechanisms on a single ServiceAccount.**
> AWS leaves the precedence undocumented when a ServiceAccount carries both the IRSA annotation (`eks.amazonaws.com/role-arn`) and is target of a `PodIdentityAssociation`. Treat this combination as unsupported.

### Step-by-Step Cutover Procedure per Workload:
1. **Provision IAM Role & Association**:
   Deploy the `pod-identity-*` Terragrunt unit for the target workload. This creates the IAM role with EKS service trust and registers the `aws_eks_pod_identity_association`.
2. **Verify Association**:
   Verify EKS has registered the association:
   ```bash
   aws eks list-pod-identity-associations --cluster-name <cluster-name>
   ```
3. **Remove IRSA Annotation**:
   Modify the workload's Helm values or Kubernetes manifests, removing the `eks.amazonaws.com/role-arn` annotation from the `ServiceAccount` metadata:
   ```diff
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: <service-account-name>
     annotations:
   -   eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/legacy-irsa-role
   ```
4. **Deploy and Roll Pods**:
   Commit the manifest changes and sync via ArgoCD. Force a rolling restart of the controller pods to clear OIDC-injected environment variables (`AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`) and pick up the Pod Identity credentials:
   ```bash
   kubectl rollout restart deployment/<controller-deployment> -n <namespace>
   ```
5. **Verify Injected Identity**:
   Exec into the running pod and check for the EKS Pod Identity mount and env variables:
   ```bash
   kubectl exec -it <pod-name> -n <namespace> -- env | grep AWS_CONTAINER_CREDENTIALS_FULL_URI
   ```
   *Expected Output*: Should contain a loopback/link-local address pointing to the local pod identity agent.
6. **Verify Workload Health**:
   Check controller logs for S3, Secrets Manager, or EC2 permission errors.

### Rollback Plan:
If a workload fails to authenticate post-migration:
1. Re-add the `eks.amazonaws.com/role-arn` annotation to the ServiceAccount values/manifest.
2. Sync via ArgoCD and restart the deployment pods.
3. Keep the `PodIdentityAssociation` in place (it does not interfere if the IRSA annotation is present and takes precedence).
4. Analyze the Pod Identity role trust policy and session tag conditions.

---

## 8. Cleanup of Legacy IRSA
Once all workloads on a cluster have successfully transitioned to EKS Pod Identity:
1. **Remove IAM Roles**: Destroy the legacy IRSA roles via Terraform/Terragrunt (e.g., delete the `eso-irsa` units).
2. **Disable OIDC Providers**: In the cluster's base Terragrunt stack/unit, disable the OIDC provider creation:
   ```hcl
   inputs = {
     enable_irsa = false
   }
   ```
3. **IAM Clean**: Remove the EKS cluster OIDC identity providers from IAM to minimize attack surface and configuration drift.
