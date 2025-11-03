# Innovate Inc. - AWS Cloud Architecture Design

**Client**: Innovate Inc. (Startup)
**Application**: Flask REST API + React SPA + PostgreSQL
**Initial Scale**: Hundreds of users/day
**Growth Target**: Millions of users
**Requirements**: Managed Kubernetes, CI/CD, strong security, cost-effective

---

## 1. Cloud Environment Structure

### Recommended AWS Account Strategy

**Phase 1 (Months 1-6): Simplified 3-Account Structure**

| Account | Purpose | Justification |
|---------|---------|---------------|
| **Management** | AWS Organizations root, consolidated billing, centralized IAM Identity Center | No workloads; serves as billing aggregator and identity hub |
| **Development** | Dev and staging environments in separate VPCs | Cost-effective for startup; isolates non-production workloads |
| **Production** | Production workloads only | Critical isolation for production; separate blast radius and access controls |

**Phase 2 (Months 6+): Scale to 5-Account Structure**

Add these accounts as the organization grows:
- **Security Account**: Centralized GuardDuty, Security Hub, AWS Config aggregation
- **Shared Services**: ECR image registry, artifact repositories, cross-account resources

### Justification

**Why start with 3 accounts?**
- Startup with limited experience needs simplicity
- Provides essential isolation (dev/staging vs production)
- Enables separate IAM policies and billing visibility
- Low overhead for small team (3-5 engineers)
- Easy migration path to multi-account as team grows

**Why not start with 7+ accounts?**
- Operational complexity too high for startup
- Increases management overhead (cross-account roles, networking)
- Harder to troubleshoot for inexperienced team
- Can delay time-to-market

**AWS Organizations Benefits**:
- Consolidated billing with cost allocation tags
- Service Control Policies (SCPs) to enforce guardrails
- Centralized CloudTrail and Config for compliance
- Volume discounts across accounts

---

## 2. Network Design

### 2.1 VPC Architecture

**VPC Configuration per Environment**

```
Development Account:
├── VPC: 10.0.0.0/16 (dev-vpc)
└── VPC: 10.1.0.0/16 (staging-vpc)

Production Account:
└── VPC: 10.10.0.0/16 (prod-vpc)
```

**Subnet Layout (per VPC, across 3 Availability Zones)**

| Subnet Type | CIDR Examples | Purpose | Internet Access |
|-------------|---------------|---------|-----------------|
| **Public** | 10.10.1.0/24, 10.10.2.0/24, 10.10.3.0/24 | Application Load Balancer, NAT Gateways | Yes (via Internet Gateway) |
| **Private-App** | 10.10.11.0/24, 10.10.12.0/24, 10.10.13.0/24 | EKS worker nodes, application pods | Outbound only (via NAT Gateway) |
| **Private-Data** | 10.10.21.0/24, 10.10.22.0/24, 10.10.23.0/24 | Aurora PostgreSQL, ElastiCache | No direct internet (VPC endpoints only) |

**Routing**:
- Public subnets → Internet Gateway (0.0.0.0/0)
- Private-App subnets → NAT Gateway (for package downloads, API calls)
- Private-Data subnets → No default route; VPC endpoints for AWS services

**VPC Endpoints** (reduce NAT costs, improve security):
- S3 (Gateway endpoint - free)
- ECR (Interface endpoint - for pulling container images)
- CloudWatch Logs (Interface endpoint - for logging)
- Secrets Manager (Interface endpoint - for database credentials)

### 2.2 Network Security

#### Security Groups (Stateful Firewall)

**ALB Security Group**:
- Inbound: 443 (HTTPS) from 0.0.0.0/0 (internet)
- Outbound: 8080 to EKS node security group

**EKS Node Security Group**:
- Inbound: 8080 from ALB security group (API traffic)
- Inbound: 443, 10250 from EKS control plane (Kubernetes API)
- Inbound: All traffic from itself (pod-to-pod communication)
- Outbound: 443 to 0.0.0.0/0 (AWS APIs via NAT or endpoints)
- Outbound: 5432 to Aurora security group

**Aurora Security Group**:
- Inbound: 5432 (PostgreSQL) from EKS node security group only
- Outbound: None required

#### Network Policies (Kubernetes Layer)

Deploy Cilium or Calico for pod-level network policies:
- Default deny all traffic between namespaces
- Explicit allow rules for:
  - Backend pods → Aurora database
  - Backend pods → Secrets Manager (via IRSA)
  - Frontend S3 sync pods → S3 (during deployment)

#### Additional Security Measures

**AWS WAF** (on Application Load Balancer):
- Block common attack patterns (SQL injection, XSS)
- Rate limiting: 2000 requests per 5 minutes per IP
- Geo-blocking if needed (block countries with no user base)

**VPC Flow Logs**:
- Enable on all VPCs → S3 bucket
- Retention: 90 days for production, 30 days for dev/staging
- Used for security auditing and troubleshooting

**Monitoring & Threat Detection**:
- GuardDuty: Threat detection on VPC Flow Logs, DNS logs
- Security Hub: Centralized security findings
- AWS Config: Track security group changes, non-compliant resources

**Encryption in Transit**:
- TLS 1.2+ termination at ALB (ACM certificate)
- Optional: mTLS between services using service mesh (Phase 2)

---

## 3. Compute Platform (Amazon EKS)

### 3.1 EKS Cluster Design

**Cluster Configuration**:
- Kubernetes Version: 1.34 (latest stable)
- Authentication: IAM + RBAC (aws-auth ConfigMap)
- Control Plane Logging: API server, audit, authenticator logs → CloudWatch
- Pod Identity: Enabled (for IRSA - IAM Roles for Service Accounts)

**Cluster per Environment**:
- `dev-eks-cluster` (Development account)
- `staging-eks-cluster` (Development account)
- `prod-eks-cluster` (Production account)

**Justification**: Separate clusters per environment provide strong isolation and prevent accidental production changes.

### 3.2 Node Groups and Scaling

#### Node Group Strategy

**System Node Group** (critical add-ons):
- Instance type: t3.medium (2 vCPU, 4 GB RAM)
- Count: 2 nodes (on-demand for reliability)
- Taint: `CriticalAddonsOnly=true:NoSchedule`
- Runs: CoreDNS, Karpenter controller, monitoring agents

**Application Node Groups** (managed by Karpenter):
Karpenter dynamically provisions nodes based on pod requirements.

**Karpenter NodePools**:

1. **x86 General-Purpose NodePool**:
   - Instance families: m6i, m7i, c6i, c7i (Intel/AMD)
   - Capacity: 80% Spot, 20% On-Demand
   - Size range: 2-32 vCPU
   - Use case: Backend API, general workloads

2. **ARM64 Graviton NodePool**:
   - Instance families: m7g, c7g, r7g (AWS Graviton2/3)
   - Capacity: 90% Spot, 10% On-Demand
   - Size range: 2-64 vCPU
   - Use case: Cost-optimized workloads (20-40% cheaper than x86)

#### Scaling Strategy

**Cluster-Level Scaling (Karpenter)**:
- Automatically provisions nodes when pods are unschedulable
- Consolidates underutilized nodes after 30 seconds
- Handles spot termination gracefully (2-minute warning)
- Bin-packing algorithm for optimal resource utilization

**Pod-Level Scaling**:
- **HorizontalPodAutoscaler (HPA)**:
  - Backend API: 3-20 replicas based on CPU (target 70%)
  - Metric: CPU + custom metrics (requests per second)
- **VerticalPodAutoscaler (VPA)**: Recommend resource requests/limits based on usage

**Scaling Targets by Phase**:
- Phase 1 (Months 1-3): 2-5 nodes, 10-50 pods
- Phase 2 (Months 4-8): 5-15 nodes, 50-200 pods
- Phase 3 (Months 9-12): 15-50 nodes, 200-1000 pods

### 3.3 Resource Allocation

**Namespace Strategy**:
```
default         # Avoid using
system          # Karpenter, monitoring, logging
backend         # Flask API pods
frontend-build  # Frontend build/deploy jobs (optional)
```

**Resource Quotas** (per namespace):
- Backend namespace: Max 50 vCPU, 100 GB memory
- Prevents resource exhaustion from runaway pods

**Pod Resource Requests/Limits**:
```yaml
Backend API Pod:
  requests:
    cpu: 250m (0.25 vCPU)
    memory: 512Mi
  limits:
    cpu: 1000m (1 vCPU)
    memory: 1Gi
```

**Priority Classes**:
- Critical: System pods (Karpenter, CoreDNS)
- High: Backend API pods
- Low: Background jobs, cron tasks

### 3.4 Containerization Strategy

#### Image Building

**Dockerfile Best Practices** (Flask backend):
```dockerfile
# Multi-stage build
FROM python:3.11-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
USER 1000  # Non-root user
ENV PATH=/root/.local/bin:$PATH
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8080", "app:app"]
```

**Build Process**:
- GitHub Actions triggers on push to main branch
- Run tests (pytest for Python, Jest for React)
- Build Docker image with BuildKit for layer caching
- Scan image with Trivy (fail on HIGH/CRITICAL CVEs)
- Tag: `{git-sha}`, `{branch}-latest`, `v{semver}` for releases

#### Container Registry

**Amazon ECR** (Elastic Container Registry):
- Private repositories per service: `innovate-backend`, `innovate-frontend-builder`
- Image scanning: Amazon Inspector (automatic on push)
- Lifecycle policy: Keep last 10 images per environment, delete untagged after 7 days
- Cross-account replication: Dev account → Production account (for promotion)
- Image signing: cosign for provenance verification

#### Deployment Process

**GitOps with ArgoCD**:

1. **Code Repository**: GitHub (application code)
2. **Image Build**: GitHub Actions builds and pushes to ECR
3. **Manifest Repository**: Separate repo with Kubernetes manifests
4. **ArgoCD**: Monitors manifest repo, syncs to cluster automatically

**Deployment Flow**:
```
Developer → Git push
    ↓
GitHub Actions → Build & Test → Push to ECR
    ↓
Update manifest repo (automated or PR)
    ↓
ArgoCD detects change → Deploy to dev
    ↓
Manual approval → Deploy to staging
    ↓
Integration tests pass → Manual approval
    ↓
Deploy to production (blue-green)
```

**Deployment Strategies**:
- Dev: Rolling update (immediate deployment)
- Staging: Canary (10% → 50% → 100% over 15 minutes)
- Production: Blue-green (zero-downtime, instant rollback)

**Health Checks**:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

## 4. Database (Amazon Aurora PostgreSQL)

### 4.1 Service Selection

**Recommended Service**: Amazon Aurora PostgreSQL

**Justification**:

| Requirement | Aurora Advantage | Alternative (RDS PostgreSQL) |
|-------------|------------------|------------------------------|
| **High Availability** | Multi-AZ with automatic failover (< 30s) | Multi-AZ with 1-2 min failover |
| **Performance** | 3x throughput vs standard PostgreSQL | Standard PostgreSQL performance |
| **Scalability** | Up to 15 read replicas, auto-scaling storage | Up to 5 read replicas, manual storage scaling |
| **Backup** | Continuous backups to S3, PITR to any second | Daily snapshots, 5-min PITR granularity |
| **Cost** | Serverless v2 option for variable workloads | Always-on instances (higher cost for low usage) |
| **Global** | Aurora Global Database for DR | Cross-region read replicas (manual setup) |

**Configuration by Environment**:

| Environment | Configuration | Cost/Month | Justification |
|-------------|--------------|------------|---------------|
| **Dev** | Aurora Serverless v2 (0.5-2 ACU) | $30-60 | Scales to zero during idle, cost-effective |
| **Staging** | Aurora Serverless v2 (1-4 ACU) | $60-120 | Handles testing load, auto-scales |
| **Production** | Aurora Provisioned: db.r6g.large Multi-AZ + 1 read replica | $450-600 | Predictable performance, HA, read scaling |

### 4.2 High Availability Architecture

**Production Configuration**:

```
Region: us-east-1
├── AZ 1: Writer instance (db.r6g.large)
├── AZ 2: Standby replica (automatic failover)
└── AZ 3: Read replica (read scaling)
```

**HA Features**:
- **Automatic Failover**: < 30 seconds to standby replica
- **Replication**: Synchronous replication to standby (zero data loss)
- **Read Replicas**: Asynchronous replication for read scaling (< 100ms lag)
- **Self-Healing Storage**: 6 copies across 3 AZs, automatic repair
- **Connection Endpoint**:
  - Writer endpoint: `prod-cluster.cluster-xxx.us-east-1.rds.amazonaws.com` (always points to writer)
  - Reader endpoint: `prod-cluster.cluster-ro-xxx.us-east-1.rds.amazonaws.com` (load balances across readers)

**Application Connection Strategy**:
- Write operations → Writer endpoint
- Read operations (reports, analytics) → Reader endpoint
- Database credentials → AWS Secrets Manager (rotated every 30 days)
- Authentication → IAM Roles for Service Accounts (IRSA) from EKS pods

### 4.3 Backup Strategy

**Automated Backups**:

| Backup Type | Frequency | Retention | Storage | RTO | RPO |
|-------------|-----------|-----------|---------|-----|-----|
| **Continuous Backup** | Real-time | 35 days (prod), 7 days (dev) | S3 (Aurora managed) | < 5 min | 5 min |
| **Daily Snapshot** | 02:00 AM UTC | 35 days (prod), 7 days (dev) | S3 | < 30 min | 24 hours |
| **Cross-Region Backup** | Daily | 7 days | S3 (us-west-2) | < 1 hour | 24 hours |

**Point-in-Time Recovery (PITR)**:
- Restore to any second within retention period
- Creates new Aurora cluster from backup
- Use case: Recover from accidental data deletion, application bug

**Backup Testing**:
- Monthly: Restore dev database from production snapshot (verify integrity)
- Quarterly: Full DR drill (restore in secondary region)

### 4.4 Disaster Recovery

**DR Strategy**: Active-Passive with Aurora Global Database (Phase 2+)

**Phase 1 (Months 1-6): Single Region**
- **RTO**: 1 hour (restore from snapshot)
- **RPO**: 5 minutes (PITR)
- **DR Process**:
  1. Create Aurora cluster from latest backup
  2. Update application endpoints in Secrets Manager
  3. Restart application pods to pick up new connection string

**Phase 2 (Months 6+): Multi-Region with Global Database**
- **Primary Region**: us-east-1 (read-write)
- **Secondary Region**: us-west-2 (read-only, DR standby)
- **Replication Lag**: < 1 second
- **RTO**: 1 minute (promote secondary to primary)
- **RPO**: < 1 second (near-zero data loss)

**Failover Process** (Phase 2):
```
1. Detect failure: Primary region unavailable (manual or automated)
2. Promote secondary cluster in us-west-2 to primary
3. Update Route 53 DNS to point to us-west-2 EKS cluster
4. Application pods reconnect to new primary database (< 1 min)
```

**Monitoring for DR Readiness**:
- CloudWatch alarm: Replication lag > 5 seconds
- Daily automated backup verification
- Quarterly DR drill with documentation

### 4.5 Performance Optimization

**Connection Pooling**:
- Use PgBouncer or SQLAlchemy connection pooling in application
- Pool size: 20 connections per pod (adjust based on load)
- Max connections on db.r6g.large: ~3000

**Query Optimization**:
- Enable Performance Insights (7-day retention free, 31-day paid)
- Identify slow queries (> 100ms) and optimize with indexes
- Use EXPLAIN ANALYZE for query planning

**Caching Strategy** (Phase 2):
- Amazon ElastiCache for Redis (session data, frequently accessed data)
- Reduces database load by 30-50%
- Cache invalidation strategy: TTL + manual invalidation on writes

---

## 5. Summary and Cost Estimate

### Architecture Overview

**Phase 1 (MVP - Months 1-3)**:
- 3 AWS accounts (Management, Development, Production)
- 3 VPCs with 3-tier subnet design
- 3 EKS clusters (dev, staging, prod) with Karpenter
- Aurora Serverless v2 for dev/staging, provisioned for production
- S3 + CloudFront for React SPA
- Basic monitoring with CloudWatch

**Total Monthly Cost (Phase 1)**: $500-800
- EKS: $219 (3 clusters × $73)
- Compute: $150-250 (EC2 nodes)
- Aurora: $100-200
- Networking: $60-80 (NAT, data transfer)
- Storage & Monitoring: $50-100

### Key Architectural Decisions

| Decision | Choice | Justification |
|----------|--------|---------------|
| **Cloud Provider** | AWS | Rich managed services ecosystem, mature EKS, Aurora PostgreSQL |
| **Kubernetes** | Amazon EKS | Managed control plane, integrates with AWS services (IAM, VPC, ALB) |
| **Autoscaling** | Karpenter | Sub-minute node provisioning, cost-optimized (Spot, Graviton) |
| **Database** | Aurora PostgreSQL | High availability, automatic failover, PITR, performance |
| **Frontend Hosting** | S3 + CloudFront | Serverless, globally distributed, cost-effective |
| **CI/CD** | GitHub Actions + ArgoCD | GitOps workflow, automated deployments, easy rollback |
| **Security** | Multi-layer (IAM, SG, Network Policies, WAF) | Defense in depth for sensitive user data |

### Scalability Path

This architecture supports growth from hundreds to millions of users:
- **Phase 1**: 100-1,000 users/day (current architecture)
- **Phase 2**: 10,000-100,000 users/day (add read replicas, ElastiCache, more nodes)
- **Phase 3**: 1M+ users/day (Aurora Global Database, multi-region EKS, service mesh)

### Next Steps

1. Set up AWS Organization and 3 accounts
2. Deploy VPCs and networking infrastructure (Terraform/Terragrunt)
3. Deploy EKS clusters and install Karpenter
4. Deploy Aurora databases
5. Containerize application and set up CI/CD pipeline
6. Deploy to development → staging → production

---

**Reference Implementation**: This repository contains Terraform/Terragrunt modules for deploying this architecture. See `terragrunt/envs/simple/` for a quick-start configuration.
