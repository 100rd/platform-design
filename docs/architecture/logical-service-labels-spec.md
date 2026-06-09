# Specification: Metadata-Driven Logical Service Representation (Labels)

This specification defines the logical service representation model using unified **labels**. It establishes how a single logical system (e.g., `auth`, `payment`) connects container workloads, cloud resources, database tiers, and object storage across both **AWS** and **GCP**, enabling unified permissions, internal network isolation, observability, and cost attribution.

---

## 1. Architectural Concept: The Logical Service Block

Instead of viewing a service as a collection of decoupled resources, we represent it as a bounded "Logical Service Block". Every resource in this block is tagged with a matching `platform.system` (or `platform:system`) label.

```
                  ┌──────────────────────────────────────────┐
                  │          LOGICAL SERVICE: "auth"         │
                  └──────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
 ┌──────────────┐              ┌──────────────┐              ┌──────────────┐
 │ EKS/GKE Pods │              │ RDS / Cloud  │              │  S3 / Cloud  │
 │  (Workloads) │              │  SQL (DB)    │              │ Storage (S3) │
 ├──────────────┤              ├──────────────┤              ├──────────────┤
 │ platform.    │              │ platform:    │              │ platform:    │
 │ system=auth  │              │ system=auth  │              │ system=auth  │
 └──────────────┘              └──────────────┘              └──────────────┘
```

---

## 2. In-Cluster Network Segregation (Cilium Network Policies)

Inside the Kubernetes cluster (EKS/GKE), Cilium CNI utilizes eBPF-based identity verification. We enforce strict default-deny micro-segmentation, permitting workloads to communicate only with peers belonging to the same logical system.

### Cilium Network Policy Definition
```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: auth-system-isolation
  namespace: workloads
spec:
  endpointSelector:
    matchLabels:
      platform.system: auth
  ingress:
    # 1. Allow traffic only from pods within the same logical system
    - fromEndpoints:
        - matchLabels:
            platform.system: auth
    # 2. Allow ingress from system ingress gateways (e.g., Cilium Gateway)
    - fromEndpoints:
        - matchLabels:
            platform.component: ingress
  egress:
    # 1. Allow egress only to pods within the same logical system
    - toEndpoints:
        - matchLabels:
            platform.system: auth
    # 2. Allow egress to DNS resolution
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
```

---

## 3. Pod/Machine Identity & Resource Access Control (AWS + GCP)

When Kubernetes pods access cloud resources (e.g., database, storage), authorization is checked dynamically based on matching labels (ABAC).

### 3.1 AWS: EKS Pod Identity + Principal Tags
AWS EKS Pod Identity maps a Kubernetes ServiceAccount to an IAM Role, propagating the pod's labels as session principal tags (`aws:PrincipalTag/platform:system`).

#### Dynamic ABAC IAM Policy for S3
This single policy allows any pod to read/write only the S3 buckets matching its own system identifier:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLabelMatchingS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/platform:system": "${aws:PrincipalTag/platform:system}"
        }
      }
    }
  ]
}
```

---

### 3.2 GCP: GKE Workload Identity + IAM Conditions
In GCP, GKE Workload Identity maps a Kubernetes ServiceAccount to a Google Service Account (GSA). GCP IAM supports resource-level label matching using **IAM Conditions**.

#### GCP IAM Policy Binding with Condition
We attach a condition to the bucket access binding, allowing the GSA (`auth-gsa@project.iam.gserviceaccount.com`) to read/write storage buckets only if the bucket carries a matching label:
```yaml
bindings:
- role: roles/storage.objectAdmin
  members:
  - serviceAccount:auth-gsa@project.iam.gserviceaccount.com
  condition:
    title: match_service_bucket
    description: Allow access only if bucket platform_system label matches
    expression: resource.matchTag("platform_system", "auth")
```

---

## 4. Human/Developer Access Control (ABAC for SSO)

To prevent manual access policy creep, developer permissions are resolved dynamically by mapping their corporate directory group/attributes to principal tags.

### 4.1 AWS IAM Identity Center (SSO)
1. **Attribute Mapping:** Map the identity provider (IdP) directory attribute `User.Department` (or a custom attribute `User.System`) to the AWS session principal tag `platform:system`.
2. **SSO Permission Set Policy:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "AllowDeveloperRdsManagement",
         "Effect": "Allow",
         "Action": [
           "rds:Describe*",
           "rds:StartDBInstance",
           "rds:StopDBInstance"
         ],
         "Resource": "*",
         "Condition": {
           "StringEquals": {
             "aws:ResourceTag/platform:system": "${aws:PrincipalTag/platform:system}"
           }
         }
       }
     ]
   }
   ```
   *Result:* An engineer in the `auth` team can only control the `auth` database.

### 4.2 GCP IAM (Google Groups + Resource Labels)
Google Cloud supports conditional IAM bindings for Google Groups. Members of `group:dev-auth@company.com` are granted resource viewer/editor permissions scoped by GCP resource labels:
```yaml
bindings:
- role: roles/cloudsql.editor
  members:
  - group:dev-auth@company.com
  condition:
    title: limit_to_auth_sql
    expression: resource.labels["platform_system"] == "auth"
```

---

## 5. Unified Observability & Cost Aggregation (FinOps)

By establishing this metadata standard, we align runtime diagnostics with financial reporting.

### 5.1 Observability: Grafana Multi-Cloud Joins
We build a standardized Grafana dashboard driven by the template variable `$system`:
* **AWS RDS CPU (CloudWatch via YACE):**
  ```promql
  aws_rds_cpu_utilization_average{tag_platform_system="$system"}
  ```
* **GCP Cloud SQL CPU (Stackdriver exporter):**
  ```promql
  stackdriver_cloudsql_database_cpu_utilization{resource_labels_platform_system="$system"}
  ```
* **Kubernetes Pods Memory (cAdvisor):**
  ```promql
  sum(container_memory_working_set_bytes) 
  * on(pod, namespace) group_left(label_platform_system) 
  kube_pod_labels{label_platform_system="$system"}
  ```

---

### 5.2 FinOps: Logical Service Cost Aggregation

#### 1. AWS Cost Optimization (OpenCost + Athena)
OpenCost queries Kubernetes CPU/Memory allocation and correlates it with AWS Cost & Usage Report (CUR) metrics:
```sql
SELECT 
  line_item_usage_start_date,
  resource_tags_user_platform_system AS system,
  SUM(line_item_unblended_cost) AS cost
FROM aws_cur_athena
WHERE resource_tags_user_platform_system = 'auth'
GROUP BY 1, 2
```

#### 2. GCP Cost Attribution (BigQuery Billing Export)
Google Cloud Billing exports granular, resource-labeled billing details directly to BigQuery. GKE cost allocation maps workload labels to the same export schema.
```sql
SELECT 
  labels.value AS system_name,
  SUM(cost) + SUM(credits.amount) AS net_cost
FROM `project.billing.gcp_billing_export_v1`
UNNEST(labels) AS labels
WHERE labels.key = "platform_system"
GROUP BY system_name
HAVING system_name = "auth"
```
*Outcome:* Platforms leads see a single cost line representing the full TCO of the `auth` system, merging K8s nodes, Cloud SQL, MemoryStore, and Storage buckets instantly.
