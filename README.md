# Platform Design

**A production-ready, cloud-native casino gaming platform with blockchain integration**

---

## 📋 Table of Contents

- [Overview](#overview)
- [What This Platform Does](#what-this-platform-does)
- [Architecture Highlights](#architecture-highlights)
- [Component Status & Versions](#component-status--versions)
- [Technical Stack](#technical-stack)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Adaptation Roadmap](#adaptation-roadmap)
- [Documentation](#documentation)

---

## Overview

This repository contains a **reference architecture and implementation** for a cloud-native casino platform that combines traditional gaming services with a private blockchain for internal transactions. It's designed as a production-ready, scalable, and compliant gaming infrastructure that follows the AWS Well-Architected Framework.

### Purpose

The platform solves several critical gaming industry challenges:

1. **High-Performance Gaming Operations**
   - Handle thousands of concurrent players
   - Sub-100ms latency for real-time gaming
   - Scalable to 1,000-5,000 Kubernetes nodes
   - 100 Gbps+ data ingest capacity

2. **Blockchain-Backed Fairness**
   - Private blockchain for in-platform transactions
   - Provably fair gaming verification
   - Immutable transaction records
   - Transparent game outcome validation

3. **Enterprise-Grade Security & Compliance**
   - Gaming regulatory compliance
   - Player data protection
   - Automated security scanning (Checkov, Trivy)
   - AWS Well-Architected Framework alignment

4. **Cost Optimization**
   - Multi-architecture support (x86 + ARM64/Graviton)
   - Spot instance integration
   - Intelligent autoscaling (designed for Karpenter)
   - 30%+ compute cost savings potential

---

## What This Platform Does

### Hybrid Cloud Strategy

The platform uses a **dual-infrastructure approach**:

#### AWS Cloud (Amazon EKS)
- Majority of application workloads
- Microservices running in Kubernetes
- Managed databases (RDS PostgreSQL)
- Object storage (S3)
- Monitoring and logging (CloudWatch)
- Scalable compute with EKS managed node groups

#### Bare Metal Servers
- Critical blockchain nodes
- High-performance, latency-sensitive workloads
- Direct hardware access for crypto operations
- Performance optimization for gaming logic
- Integration via Hetzner Cloud

### Core Capabilities

1. **Multi-Team Application Deployment**
   - Organized by team: Direct, Mono, Protocols, Chains, Listeners
   - GitOps-driven via ArgoCD ApplicationSets
   - Automated deployment pipelines

2. **Data Processing Pipeline**
   - Real-time event streaming (Kafka)
   - Time-series telemetry (InfluxDB)
   - Session management (Redis)
   - Transaction storage (PostgreSQL, MongoDB)

3. **Observability & Monitoring**
   - Metrics: Prometheus + Thanos + Grafana
   - Logs: Fluent Bit → Loki/Elasticsearch
   - Traces: Tempo with OpenTelemetry
   - Cost monitoring via AWS Cost Explorer

4. **Security & Secrets Management**
   - HashiCorp Vault integration
   - External Secrets Operator
   - Network policies (Cilium CNI)
   - mTLS via SPIRE
   - Cloudflare WAF protection

---

## Architecture Highlights

### Multi-Environment Setup
- AWS hosts majority of workloads using EKS
- Bare metal servers run critical blockchain components
- Kubernetes as uniform runtime across environments

### Containerized Services
- All applications built as Docker images
- Helm charts define service deployments
- Kustomize provides environment-specific overlays

### GitOps Pipeline
- Infrastructure defined in Terraform and stored in Git
- ArgoCD watches repository and applies manifests automatically
- GitHub Actions manage CI pipeline (tests, builds, security scans)

### Observability and Security
- Metrics gathered via Prometheus with Grafana dashboards
- Logs centralized through Loki or Elasticsearch
- Vault handles secrets management
- Cloudflare protects external endpoints

### Blockchain Integration
- Internal crypto nodes run on dedicated hardware
- Services interact via gRPC APIs written in Go
- Provably fair gaming implementation

---

## Component Status & Versions

### Infrastructure Components

| Component | Current Version | Latest Version | Status | Action Required |
|-----------|----------------|----------------|--------|-----------------|
| **Terraform AWS VPC Module** | 6.5.0 | 6.5.0 | ✅ **UP TO DATE** | None |
| **Terraform AWS EKS Module** | 21.8.0 | 21.8.0 | ✅ **UP TO DATE** | None |
| **EKS Cluster Version** | 1.34 | 1.34 | ✅ **CURRENT** | None |
| **Karpenter Module** | Not implemented | v1.1.1 | ❌ **MISSING** | Create module |
| **Karpenter NodePools** | Not implemented | v1 | ❌ **MISSING** | Create configs |
| **VPC Module** | ✅ Implemented | - | ✅ **WORKING** | Needs version bump |
| **Hetzner Nodes Module** | ✅ Implemented | - | ✅ **WORKING** | Review only |

### Application Components

| Component | Current Version | Status | Notes |
|-----------|----------------|--------|-------|
| **ArgoCD ApplicationSet** | v1 | ✅ **WORKING** | GitOps ready |
| **External Secrets Operator** | Helm chart | ✅ **WORKING** | Deployed via ArgoCD |
| **Generic App Helm Chart** | v1 | ✅ **WORKING** | Ingress + secrets |
| **Network Policies** | K8s v1 | ✅ **WORKING** | Baseline policies |
| **Example Services (Go)** | - | ✅ **WORKING** | example-api, hello-world |

### CI/CD & Security

| Component | Status | Notes |
|-----------|--------|-------|
| **Checkov Security Scanning** | ✅ **ACTIVE** | AWS Well-Architected checks |
| **Trivy Image Scanning** | ✅ **ACTIVE** | Container vulnerability scanning |
| **GitHub Actions Workflows** | ✅ **ACTIVE** | helm-validate, yaml-lint, secret-scan |
| **Pre-commit Hooks** | 📋 **PLANNED** | Terraform fmt, validate |

### Documentation

| Component | Status | Quality |
|-----------|--------|---------|
| **Platform Overview** | ✅ Complete | Excellent |
| **Tech Stack** | ✅ Complete | Good |
| **Scale Patterns** | ✅ Complete | Excellent (1k-5k nodes) |
| **Terragrunt Strategy** | ✅ Complete | Excellent |
| **Usage README** | ⚠️ **BASIC** | Needs expansion |
| **Multi-arch Examples** | ❌ **MISSING** | Must create |

---

## Technical Stack

### Infrastructure & DevOps
- **AWS** – EKS, EC2, RDS, S3, CloudWatch
- **Bare Metal** – Hetzner Cloud for blockchain nodes
- **Kubernetes** – Cluster orchestration (Helm, Kustomize)
- **Terraform** – Infrastructure as Code
- **Terragrunt** – DRY Terraform configuration
- **ArgoCD** – GitOps deployment management
- **Cloudflare** – DNS, CDN, WAF
- **GitHub Actions** – CI/CD pipelines
- **Docker** – Container packaging

### Data Stores
- **PostgreSQL** – Primary relational store
- **MongoDB** – Document database for flexible schemas
- **Kafka** – Message streaming and event distribution
- **Redis** – In-memory caching and ephemeral data
- **InfluxDB** – Time-series telemetry (scale-patterns design)

### Languages & Frameworks
- **Golang** – Primary language for backend services and blockchain modules
- **Node.js** – Supporting tooling and lightweight frontends
- **Swagger/OpenAPI** – API documentation and client generation

### Observability
- **Prometheus & Thanos** – Metrics collection and long-term storage
- **Grafana** – Metrics visualization
- **Loki / Elasticsearch** – Log aggregation
- **Tempo** – Distributed tracing
- **OpenTelemetry** – Observability instrumentation

### Security
- **HashiCorp Vault** – Secrets management
- **External Secrets Operator** – K8s secrets from Vault
- **Cilium CNI** – eBPF-based networking and security
- **SPIRE** – mTLS service identity
- **OPA/Gatekeeper** – Policy enforcement (planned)

---

## Repository Structure

```
platform-design/
├── docs/                           # Platform documentation
│   ├── platform-overview.md        # Architecture overview
│   ├── 01-tech-stack.md           # Technology decisions
│   ├── 02-terragrunt-strategy.md  # Terragrunt usage guide
│   └── scale-patterns.md          # 1k-5k node scaling design
│
├── terraform/                      # Infrastructure as Code
│   ├── modules/
│   │   ├── vpc/                   # VPC with public/private subnets
│   │   ├── eks/                   # EKS cluster configuration
│   │   └── hetzner-nodes/         # Bare metal node integration
│   └── README.md
│
├── terragrunt/                     # Terragrunt configuration
│   ├── terragrunt.hcl             # Root config (backend, provider)
│   └── envs/
│       ├── dev/                   # Dev environment
│       └── prod/                  # Production environment
│
├── apps/                           # Application Helm charts
│   ├── infra/                     # Infrastructure components
│   │   └── external-secrets/      # External Secrets Operator
│   ├── direct/                    # Direct team applications
│   ├── mono/                      # Monolithic applications
│   ├── protocols/                 # Protocol services
│   ├── chains/                    # Blockchain nodes
│   └── listeners/                 # Event listeners and workers
│
├── helm/                           # Helm chart templates
│   └── app/                       # Generic application chart
│       ├── templates/
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── ingress.yaml
│       │   └── externalsecret.yaml
│       └── values.yaml
│
├── argocd/                         # ArgoCD configurations
│   └── applicationset.yaml        # ApplicationSet for auto-discovery
│
├── network-policies/               # Kubernetes NetworkPolicy
│   ├── default-deny-all.yaml
│   ├── allow-dns-egress.yaml
│   └── allow-from-same-namespace.yaml
│
├── services/                       # Example microservices
│   ├── example-api/               # Go REST API with health checks
│   └── hello-world/               # Prometheus metrics example
│
├── .github/workflows/              # CI/CD pipelines
│   ├── well-architected.yml       # Checkov + Trivy scanning
│   ├── helm-validate.yml          # Helm chart validation
│   ├── yaml-lint.yml              # YAML linting
│   └── secret-scan.yml            # Secret detection
│
└── checkov-policies/               # Custom Checkov policies
    └── (AWS Well-Architected alignment)
```

---

## Getting Started

### Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.0
- kubectl
- AWS CLI configured
- (Optional) Terragrunt for simplified multi-environment management

### Quick Start: Deploy Example Service

```bash
# Build and run example API locally
cd services/example-api
docker build -t example-api .
docker run -p 8080:8080 example-api

# Test health endpoint
curl http://localhost:8080/health
```

### Deploy Infrastructure with Terraform

```bash
cd terraform/modules
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
```

Variables such as AWS region and cluster name can be overridden via `terraform.tfvars` or environment variables.

### Deploy Infrastructure with Terragrunt (Recommended)

```bash
# Deploy entire dev environment
cd terragrunt/envs/dev
terragrunt run-all apply

# Deploy specific component
cd terragrunt/envs/dev/vpc
terragrunt apply
```

Terragrunt handles dependency ordering automatically (VPC → EKS → Apps).

### Connect to Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Verify connection
kubectl get nodes
```

---

## Adaptation Roadmap

This platform is being adapted to focus on **EKS + Karpenter with multi-architecture support**. The following work is in progress:

### Phase 1: Foundation Updates ✅ COMPLETED

- [x] **Update Terraform modules to latest versions**
  - VPC: 5.1.1 → 6.5.0 ✅
  - EKS: 19.15.3 → 21.8.0 ✅
  - Fix EKS version: 1.33 (invalid) → 1.34 ✅

- [ ] **Audit AWS provider compatibility**
  - Ensure modules work with latest AWS provider
  - Test IAM role configurations

### Phase 2: Karpenter Implementation ❌ MISSING

- [ ] **Create Karpenter Terraform module**
  - Karpenter controller installation
  - IAM roles and IRSA configuration
  - Service account setup
  - CRD installation

- [ ] **Create Karpenter NodePool configurations**
  - x86 NodePool (m6i, c6i, r6i families)
  - ARM64/Graviton NodePool (m7g, c7g, r7g families)
  - Spot + On-Demand mix
  - Consolidation policies

### Phase 3: Multi-Architecture Examples ❌ MISSING

- [ ] **Create Kubernetes example deployments**
  - `kubernetes/deployments/x86-example.yaml`
  - `kubernetes/deployments/graviton-example.yaml`
  - Node selector documentation
  - Architecture affinity examples

- [ ] **Update Helm chart templates**
  - Add nodeSelector support
  - Add affinity/anti-affinity
  - Document multi-arch patterns

### Phase 4: Documentation & Testing 📝 PLANNED

- [ ] **Comprehensive README**
  - End-to-end deployment guide
  - Developer workflow examples
  - Troubleshooting section
  - Cost optimization tips

- [ ] **Testing & Validation**
  - Terraform plan validation
  - Security scanning (tfsec/checkov)
  - Cost estimation (Infracost)
  - End-to-end cluster deployment test

---

## Documentation

### Architecture & Design
- [Platform Overview](docs/platform-overview.md) – High-level architecture
- [Tech Stack](docs/01-tech-stack.md) – Technology decisions and rationale
- [Scale Patterns](docs/scale-patterns.md) – Scaling to 1,000-5,000 nodes (Datadog-like telemetry)

### Deployment & Operations
- [Terragrunt Strategy](docs/02-terragrunt-strategy.md) – Multi-environment Terraform management
- [Terraform README](terraform/README.md) – Infrastructure deployment guide

### Applications
- [Apps README](apps/README.md) – Application Helm charts structure
- [Generic Helm Chart](helm/app/README.md) – Reusable application template

---

## Compliance Checks

### Automated Security Scanning

A GitHub Actions workflow (`.github/workflows/well-architected.yml`) runs:

1. **Checkov** against Terraform code
   - Custom policies in `checkov-policies/` directory
   - Maps to AWS Well-Architected Framework best practices
   - Fails on HIGH/CRITICAL issues

2. **Trivy** container image scanning
   - Scans `services/example-api` Docker image
   - Fails on HIGH/CRITICAL vulnerabilities
   - Integrated into PR checks

### AWS Well-Architected Framework Alignment

The platform is designed around five pillars:
- **Operational Excellence** – GitOps, automated deployments, monitoring
- **Security** – IAM roles, network policies, secrets management, scanning
- **Reliability** – Multi-AZ, auto-scaling, health checks
- **Performance Efficiency** – Multi-arch, spot instances, caching
- **Cost Optimization** – Graviton, spot, autoscaling, consolidation

---

## Scale Targets

Designed to support (from `docs/scale-patterns.md`):

| Metric | Target |
|--------|--------|
| **Kubernetes Nodes** | 1,000 - 5,000 |
| **Pods** | 100,000+ |
| **Data Ingest** | 100 Gbps+ |
| **API Latency** | <100ms P99 |
| **DNS Latency** | <30ms P99 |
| **Node Provisioning** | <60 seconds |
| **Scale Rate** | 2,000 nodes/min |

---

## License

See [LICENSE](LICENSE) file for details.

---

## Contributing

This is a reference architecture. Contributions welcome for:
- Karpenter implementation
- Multi-architecture examples
- Security improvements
- Documentation enhancements

---

**Built for production gaming workloads. Designed for scale. Optimized for cost.**
