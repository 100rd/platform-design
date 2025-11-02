# Innovate Inc. Cloud Architecture Design

## 1. Overview
- **Platform**: Flask REST API backend, React SPA frontend, PostgreSQL database.
- **Workload Profile**: Low initial traffic (hundreds of users/day) with planned growth to millions; handles sensitive user data.
- **Deployment Goals**: CI/CD with automated testing and gated promotion between environments.
- **Design Principles**: Follow AWS Well-Architected Framework pillars (operational excellence, security, reliability, performance efficiency, cost optimization, sustainability).
- **Implementation Footprint**: Terraform/Terragrunt definitions under [`terraform/`](../terraform/) and `network`/`kubernetes` modules in this repo provide reusable building blocks for the described architecture.

## 2. AWS Account & Organizational Structure
| Account | Purpose | Key Services | Notes |
| --- | --- | --- | --- |
| **Organization Management** | Root/management account for consolidated billing, AWS Organizations, SCPs. | AWS Organizations, IAM Identity Center. | No workloads deployed. |
| **Security** | Centralized security tooling. | GuardDuty, Security Hub, IAM Access Analyzer, AWS Config, KMS CMKs. | Aggregates findings from all member accounts; enforces detective controls. |
| **Shared Services** | Houses global services that span environments. | AWS SSO, CodeCommit/CodeBuild (if required), Artifact repositories, PrivateLink endpoints. | Limited workloads; network hub for VPC sharing if needed. |
| **Networking** | Optional dedicated account for VPC, Transit Gateway, Direct Connect. | VPCs, Route 53, Transit Gateway. | Enables clear separation of network infrastructure. |
| **Sandbox/Dev** | Developer experimentation with guardrails. | EKS (dev), Aurora PostgreSQL (serverless), supporting services. | Lower cost configurations with tighter quotas. |
| **Staging** | Pre-production validation mirroring production. | EKS (staging), Aurora (provisioned smaller instance), S3, ECR. | Used for performance/security testing. |
| **Production** | Mission-critical workloads. | EKS (prod), Aurora PostgreSQL (Multi-AZ), ElastiCache, S3. | Strict change control, least-privilege access. |

**Justification**:
- Provides blast-radius reduction and billing clarity.
- Simplifies application of service control policies (SCPs) and IAM boundaries per environment.
- Enables isolated CI/CD promotion by cross-account artifact replication (e.g., ECR image replication via lifecycle policies).

## 3. Network Architecture
### 3.1 VPC Topology
- One VPC per environment (Dev/Staging/Prod) with CIDR ranges that do not overlap; optionally shared via AWS RAM from Networking account.
- **Subnets** (per AZ, minimum 3 AZs in production):
  - Public subnets: Internet-facing Application Load Balancer (ALB) + managed NAT gateways.
  - Private app subnets: EKS worker nodes and internal load balancers.
  - Private data subnets: Aurora PostgreSQL, ElastiCache, and stateful services.
- **Routing**: Public subnets route to IGW; private app subnets route to NAT GW for egress; data subnets have no egress except VPC endpoints.
- **Endpoints**: Interface endpoints for SSM, ECR, CloudWatch, Secrets Manager; Gateway endpoint for S3 (SPA hosting and artifact retrieval).

### 3.2 Network Security
- **Segmentation**: Security groups for ALB, EKS nodes, Aurora cluster; NACLs with least-privilege rules.
- **Ingress**: ALB protected by AWS WAF and Shield Advanced (prod). SPA served via private S3 bucket fronted by CloudFront with Origin Access Control; CloudFront integrated with WAF.
- **East-West Controls**: Cilium network policies (see [`network-policies/`](../network-policies/)) enforce pod-level traffic restrictions. Calico or Cilium eBPF used for fine-grained policies.
- **Secrets & Encryption**: KMS CMKs for EBS, EFS, Aurora, S3. TLS termination at ALB and mTLS between services via service mesh (Istio per [`kubernetes/`](../kubernetes/) profiles).
- **Observability & Audit**: VPC Flow Logs to centralized logging account; Route 53 resolver query logs; GuardDuty for threat detection.

## 4. Compute Platform (Amazon EKS)
### 4.1 Cluster Layout
- Separate EKS clusters per environment. Use infrastructure-as-code modules under [`EKS-cluster-design/`](../EKS-cluster-design/) and `kubernetes/` overlays.
- System namespace hosts core add-ons: VPC CNI, CoreDNS, KubeProxy, AWS Load Balancer Controller, Cluster Autoscaler/Karpenter, ExternalDNS (private hosted zones), Fluent Bit/Vector for logging, Prometheus/Grafana stack.

### 4.2 Node Groups & Scaling
- **Node Groups**:
  - System node group (t3.medium/t4g.medium) for critical add-ons.
  - General-purpose node groups (m5/m6i family) for API workloads.
  - Compute-optimized node group (c6i) for bursty tasks.
  - Spot-backed node group for background jobs with Pod Disruption Budgets.
- **Scaling Strategy**:
  - Cluster Autoscaler or Karpenter for dynamic node provisioning based on pending pods.
  - Horizontal Pod Autoscaler (HPA) and Vertical Pod Autoscaler (VPA) for workload tuning.
  - Utilize priority classes to protect critical services.
- **Resource Allocation**: Namespaces per microservice domain with ResourceQuotas & LimitRanges to prevent noisy neighbor issues.

### 4.3 Deployment Workflows
- Git-based workflows (e.g., GitHub Actions) produce OCI images using Docker/BuildKit. Images stored in Amazon ECR with vulnerability scans via Amazon Inspector.
- Helm charts or Kustomize overlays housed in [`kubernetes/`](../kubernetes/) manage manifests. Argo CD (see [`argocd/`](../argocd/)) provides GitOps continuous delivery with environment-specific application sets.
- Progressive delivery via canary or blue/green using AWS App Mesh/Istio traffic shifting. Automated rollbacks on failed health probes.

## 5. Application Delivery & SPA Hosting
- React SPA bundled artifacts stored in S3 bucket within VPC (block public access). VPC endpoint and CloudFront distribution serve assets securely; CloudFront logs go to centralized account.
- API traffic routed through ALB to EKS Ingress Controller. Private REST endpoints accessible via API Gateway Private Integration if future microservices require it.
- CI/CD pipeline promotes artifacts across accounts using CodePipeline or GitHub Actions with OIDC; manual approval before production.

## 6. Data Platform (Aurora PostgreSQL)
- **Service Choice**: Amazon Aurora PostgreSQL Serverless v2 for Dev/Sandbox; Provisioned Multi-AZ cluster for Staging/Prod to handle predictable baseline load with autoscaling read replicas.
- **Connectivity**: Aurora placed in dedicated data subnets with no public access. EKS workloads connect via Secrets Manager credentials and IAM Roles for Service Accounts (IRSA).
- **High Availability**: Multi-AZ writer with at least two reader instances. Use Aurora Global Database for cross-region DR when scaling to millions of users.
- **Backups & DR**:
  - Automated continuous backups with PITR (7–35 days retention depending on environment).
  - Daily snapshots replicated to backup account via copy automation.
  - Database activity streams shipped to Kinesis for auditing.
  - Runbook for cross-region failover using AWS DMS or Aurora Global Database secondary region.
- **Maintenance**: Parameter groups tuned for workload; performance insights enabled. Regular schema migrations orchestrated via Liquibase/Flyway jobs in CI/CD.

## 7. Security & Compliance
- Centralized identity via IAM Identity Center with least-privilege permission sets per account.
- Enforce MFA, SCP guardrails (deny public S3 buckets, restrict IAM wildcard).
- Secrets stored in AWS Secrets Manager, rotated automatically. IRSA for pods to fetch secrets.
- ECR lifecycle policies & signing (cosign) ensure provenance. Admission controllers (OPA/Gatekeeper) enforce security baselines.
- Regular penetration testing & dependency scanning integrated into CI/CD.

## 8. Observability & Operations
- Metrics: Prometheus -> AMP (Amazon Managed Prometheus) & Grafana dashboards.
- Logs: Fluent Bit -> CloudWatch Logs -> Kinesis Firehose -> S3/Opensearch for analytics.
- Traces: AWS Distro for OpenTelemetry exporting to X-Ray or AMP.
- Incident Response: PagerDuty/SNS alerts, runbooks stored in Confluence, chaos engineering in staging.

## 9. Cost & Scaling Considerations
- Use Savings Plans/Reserved Instances for baseline node groups; spot for non-critical workloads.
- S3 Intelligent-Tiering for artifacts, lifecycle to Glacier.
- Regular cost allocation via tags/Cost Explorer; budgets and anomaly detection alerts.

## 10. Future Enhancements
- Evaluate service mesh policy automation with Cilium + Istio integration.
- Add data lake ingestion via AWS Glue when analytics needs grow.
- Introduce multi-region active-active once user base justifies latency improvements.
