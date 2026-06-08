# ADR-0028: Unified Platform Tagging and Labeling Taxonomy

- Status: **Accepted**
- Date: 2026-06-08
- Authors: platform-team, observability, FinOps
- Related issues: epic #252, ADR-0012, ADR-0026, ADR-0027
- Supersedes: (none)
- Superseded by: (none)

## Context

Our platform components are split across two distinct planes:
1. **AWS Infrastructure Plane:** Managed via Terragrunt/Terraform (e.g., RDS databases, S3 buckets, KMS keys, IAM roles).
2. **Kubernetes Workload Plane:** Managed via ArgoCD/Helm (e.g., Deployments, Argo Rollouts, Pods, Services, ServiceAccounts).

Currently, there is no standardized taxonomy to link these two planes. A logical application service—for example, the **`auth` service**—consists of an RDS database, an S3 bucket, and a set of EKS pods. Because these resources are not tagged or labeled with a unified taxonomy:
* We cannot build single-pane-of-glass Grafana dashboards showing a service's host metrics (RDS) alongside its container metrics (EKS).
* FinOps cost allocation ([ADR-0027](file:///Users/lo/Develop/multi-team-agentic/project/platform-design/docs/adrs/0027-kubernetes-cost-opencost-cur.md)) cannot easily map shared or distributed cloud costs back to a logical system.
* Security impact analysis is difficult during incident response (e.g., matching a compromised pod to its backend database).

We need a unified metadata standard to group AWS physical resources and Kubernetes virtual workloads logically.

## Decision

Adopt a **Unified Platform Tagging and Labeling Taxonomy** based on five core keys, applied as AWS Resource Tags on the infrastructure plane and Kubernetes Labels on the workload plane.

### 1. The Core Taxonomy Keys

| Key (AWS Tag) | Key (K8s Label) | Description | Example Values |
|---|---|---|---|
| `platform:system` | `platform.system` | The logical service or system boundary | `auth`, `payment`, `analytics`, `ingest` |
| `platform:component` | `platform.component` | The architectural tier/role of the resource | `database`, `cache`, `compute`, `ingress` |
| `platform:env` | `platform.env` | The deployment environment | `production`, `staging`, `dev`, `sandbox` |
| `platform:owner` | `platform.owner` | The engineering team responsible for the resource | `team-sec`, `team-checkout`, `team-data` |
| `platform:managed-by` | `platform.managed-by` | The tool orchestrating the resource | `terragrunt`, `argocd` |

### 2. AWS Plane Implementation (Terragrunt/Terraform)
Enforce these tags globally using Terragrunt's root `terragrunt.hcl` configuration. All child Terraform modules must accept and apply a `tags` variable containing these default tags:

```hcl
# terragrunt.hcl (root)
inputs = {
  tags = {
    "platform:system"     = "auth"
    "platform:component"  = "database"
    "platform:env"        = "production"
    "platform:owner"      = "team-sec"
    "platform:managed-by" = "terragrunt"
  }
}
```

### 3. Kubernetes Plane Implementation (GitOps/ArgoCD)
Enforce these labels on all Kubernetes resources (Namespaces, ArgoCD Applications, Deployments, Pods, Services, and ServiceAccounts). Helm charts and ApplicationSet templates must propagate these labels:

```yaml
# deployment.yaml (template)
metadata:
  name: auth-server
  labels:
    platform.system: "auth"
    platform.component: "compute"
    platform.env: "production"
    platform.owner: "team-sec"
    platform.managed-by: "argocd"
```

### 4. Observability & Dashboard Consolidation (Prometheus/Grafana)

To merge metrics from the AWS plane and the EKS plane in Prometheus/Grafana:

1. **Kubernetes Metrics:** **Kube-State-Metrics** is configured to expose pod labels. We can join workload metrics (e.g., CPU, Memory) with our taxonomy labels using a Prometheus query join:
   ```promql
   container_cpu_usage_seconds_total{container!=""}
   * on (pod, namespace) group_left(label_platform_system, label_platform_component)
   kube_pod_labels
   ```
2. **AWS CloudWatch Metrics:** **YACE (Yet Another CloudWatch Exporter)** scrapes metrics from CloudWatch (RDS, S3, DynamoDB) and translates AWS resource tags into Prometheus label headers:
   ```promql
   aws_rds_cpu_utilization_average{tag_platform_system="auth"}
   ```
3. **Grafana Dashboards:** We can now build dashboards driven by a single `$system` template variable (e.g., `auth`). Selecting `auth` will dynamically render:
   * **Compute (EKS):** CPU/RAM usage of pods matching `label_platform_system="auth"`.
   * **Database (RDS):** CPU, memory, and disk IOPS of DBs matching `tag_platform_system="auth"`.
   * **Storage (S3):** Bucket size and request rates matching `tag_platform_system="auth"`.
   * **Cost (OpenCost):** Direct and shared cost allocation of the `auth` namespace and databases.

## Alternatives considered

### Alternative A: Status quo (separate unlinked taxonomies)
Keep AWS tags and Kubernetes labels separate with no common keys.
*Rejected because:* It prevents building unified service-level dashboards and complicates FinOps cost consolidation.

### Alternative B: Rely solely on Kubernetes Namespaces
Group everything in a namespace and assume the namespace name is the service.
*Rejected because:* An application service often spans multiple resources *outside* Kubernetes (e.g., an RDS DB in AWS cannot live inside a K8s namespace). We need a metadata link that transcends the cluster boundary.

## Consequences

### Positive
* **Single Pane of Glass:** Teams can view their entire service topology (RDS, S3, Pods) on a single Grafana board by selecting a single filter variable.
* **Accurate FinOps Billing:** Direct and indirect costs can be aggregated by `platform.system` / `platform:system` to show the true total cost of ownership (TCO) of a service.
* **eBPF-driven Network Security:** CiliumNetworkPolicies can leverage `platform.system` labels to restrict network paths (e.g. allowing `platform.system: payment` compute pods to connect only to `platform.system: payment` databases).
* **Incident Response:** SREs can immediately identify the owner (`platform.owner`) and components of a failing system.

### Negative
* **Compliance Overhead:** Requires strict enforcement. If a team spins up an untagged RDS instance or EKS pod, it will not appear on dashboards or cost reports.
* **Migration Effort:** Existing Terraform code and Helm charts must be refactored to propagate these tags/labels.

### Risks
* **Tag Key Mismatch:** Differing cases or formats (e.g., `platform-system` vs `platform_system`) will break joins. 
  * *Mitigation:* We enforce strict linter rules (Checkov/TFLint for Terraform, Kyverno policies/ValidatingAdmissionPolicies for EKS) that block deployment of resources missing the exact required casing and keys.

## Implementation notes

1. **Terragrunt Update:** Modify the root `terragrunt.hcl` to inject default tags.
2. **Kyverno Policies:** Add a Kyverno policy in `observe` mode that alerts on any Pod or Service missing the `platform.system`, `platform.component`, or `platform.owner` labels; promote to `enforce` mode in the next phase.
3. **YACE Config:** Update the YACE configuration file to enable tag propagation for RDS, S3, and DynamoDB.
4. **Grafana Dashboard Template:** Author a standard Grafana dashboard JSON template incorporating the `$system` variables and publish it in the GitOps repository.

## References

- AWS Resource Tagging Best Practices:
  <https://docs.aws.amazon.com/whitepapers/latest/tagging-best-practices/tagging-best-practices.html>
- Kubernetes Labels and Selectors:
  <https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/>
- YACE Tag-to-Label Propagation:
  <https://github.com/nerdswords/yet-another-cloudwatch-exporter#features>
- Related: ADR-0012 (ApplicationSet Selectors), ADR-0026 (Observability), ADR-0027 (FinOps)
