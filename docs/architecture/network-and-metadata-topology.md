# Network Topology, Connectivity, and Metadata Taxonomy Blueprint

This document defines the network architecture, component connectivity, and unified labeling/tagging taxonomy used to bind AWS physical infrastructure (like RDS and S3) with EKS virtual workloads (pods and namespaces) for unified observability, security, and billing.

---

## 1. Network Structure & Component Connectivity

The platform uses a hybrid network model combining **AWS Transit Gateway (TGW)** for coarse-grained network segmentation and **VPC Lattice** as a secure, IAM-authorized TCP/HTTP service fabric. 

### 1.1 High-Level Network Architecture

```mermaid
graph TD
    subgraph AWS Cloud Plane
        TGW[AWS Transit Gateway - Hub]
        Lattice[AWS VPC Lattice Service Network]

        subgraph Hub / Network VPC
            IngressNLB[Internet-facing NLB]
            Route53[Route53 Resolvers / PHZ]
        end

        subgraph Spoke VPC: Prod
            EKSProd[EKS Cluster: Prod]
            RDSProd[(RDS PostgreSQL Prod)]
        end

        subgraph Spoke VPC: Dev/Staging
            EKSDev[EKS Cluster: Dev]
            RDSDev[(RDS PostgreSQL Dev)]
        end
    end

    %% Network Connections
    IngressNLB -->|Routes Ingress| EKSProd
    EKSProd <-->|Coarse routing / VPN| TGW
    EKSDev <-->|Coarse routing| TGW
    
    %% VPC Lattice Connections
    EKSProd -.->|Lattice Service Association| Lattice
    Lattice -.->|IAM Auth TCP target| RDSProd
    EKSDev -.->|Lattice Service Association| Lattice
    Lattice -.->|IAM Auth TCP target| RDSDev

    %% Cilium In-Cluster Network
    subgraph EKS Pod Network (Cilium eBPF)
        GatewayAPI[Cilium Gateway API Ingress] -->|Envoy L7 Routing| AppPod[Application Pods]
        AppPod -->|eBPF Network Policy| CoreDNS[CoreDNS]
    end

    EKSProd --- EKS Pod Network
```

### 1.2 Connectivity Flow Details
1. **Coarse Segmentation (TGW):** The Transit Gateway manages routing tables that separate environments. By default, Spokes (Dev/Staging VPC) cannot route IP traffic to the Prod VPC, isolating environments at the network layer.
2. **Service Mesh & Ingress (Cilium + Envoy):** Inbound traffic hits the NLB in the Network VPC, which routes to the Cilium Gateway API. Cilium uses Envoy for L7 load balancing and route matching before routing traffic over the eBPF datapath to individual pods.
3. **Stateful Resource Access (VPC Lattice):** Rather than routing database traffic directly via IP routing (which requires complex security groups and peering), EKS pods communicate with RDS databases through **VPC Lattice**. 
   * Lattice exposes the database as a local DNS endpoint (`db-auth.staging.lattice.local`).
   * Traffic is intercepted by the Lattice controller, validated via AWS SigV4 (IAM Pod Identity), and securely routed to the RDS endpoint.

---

## 2. Unified Metadata Taxonomy (AWS + EKS + RDS)

The core mechanism for joining EKS workloads with AWS resources is the **Unified Platform Tagging and Labeling Taxonomy** defined in [ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md). It uses five matching keys across both planes.

### 2.1 The Label Binding Map

```
   AWS Infrastructure (Terragrunt Tags)              EKS Kubernetes Workloads (GitOps Labels)
  ┌─────────────────────────────────────┐            ┌─────────────────────────────────────────┐
  │ Resource: aws_db_instance.auth_db   │            │ Resource: Pod / Deployment / Namespace  │
  ├─────────────────────────────────────┤            ├─────────────────────────────────────────┤
  │ platform:system     = "auth"        │ ◄────────▶ │ platform.system     = "auth"            │
  │ platform:component  = "database"    │            │ platform.component  = "compute"         │
  │ platform:env        = "production"  │            │ platform.env        = "production"      │
  │ platform:owner      = "team-sec"    │            │ platform.owner      = "team-sec"        │
  │ platform:managed-by = "terragrunt"  │            │ platform.managed-by = "argocd"          │
  └─────────────────────────────────────┘            └─────────────────────────────────────────┘
                     │                                                    │
                     │ Metric:                                            │ Metric:
                     │ aws_rds_cpu_utilization                            │ container_cpu_usage_seconds_total
                     ▼                                                    ▼
             ┌──────────────────────────────────────────────────────────────────┐
             │                   Prometheus / Grafana Join                      │
             │           Joined by key: platform:system = auth                  │
             └──────────────────────────────────────────────────────────────────┘
```

---

## 3. How Observability Join Works in Practice

### 3.1 Metric Join (PromQL)

To construct a single dashboard for the `auth` service showing EKS pods and RDS databases together:

1. **Pod Metrics:** Collected by Prometheus from EKS node cAdvisor:
   ```promql
   sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod, namespace)
   ```
2. **Pod Labels:** Kube-State-Metrics exposes labels as the `kube_pod_labels` metric:
   ```promql
   kube_pod_labels{label_platform_system="auth", label_platform_component="compute"}
   ```
3. **RDS Metrics:** Collected from CloudWatch using YACE (Yet Another CloudWatch Exporter), which maps AWS tags directly to labels:
   ```promql
   aws_rds_cpu_utilization_average{tag_platform_system="auth", tag_platform_component="database"}
   ```
4. **The Grafana Dashboard Join:** Grafana uses the common variable `$system = "auth"`. The panels fetch:
   * **Compute Panel:**
     ```promql
     sum(rate(container_cpu_usage_seconds_total[5m])) 
     * on(pod, namespace) group_left(label_platform_system) 
     kube_pod_labels{label_platform_system="$system"}
     ```
   * **Database Panel:**
     ```promql
     aws_rds_cpu_utilization_average{tag_platform_system="$system"}
     ```

### 3.2 Logs and Traces Correlation
* **Loki Log Aggregation:** Grafana Alloy reads Pod logs and formats the labels: `{platform_system="auth", platform_component="compute"}`. CloudWatch Log Forwarder ships RDS logs enriched with `{platform_system="auth", platform_component="database"}`.
* **OTel Distributed Tracing:** App traces carry span attributes (`platform.system = auth`). When an SQL query is executed, it propagates the system identifier to Tempo, allowing an engineer to click a slow query span and jump directly to the database metrics and logs.

### 3.3 Security & Admission Enforcement
The metadata taxonomy is enforced declaratively to prevent configuration drift:
* **Kyverno Policy:** Blocks deployment of any EKS pod in non-sandbox namespaces missing the `platform.system` or `platform.owner` labels.
* **AWS SCP / Checkov:** Enforces that all RDS and S3 instances carry the `platform:system` tag at creation time, otherwise deployment fails.
