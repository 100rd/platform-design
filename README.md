# Platform Design

Production-grade, multi-account AWS platform with EKS, Karpenter autoscaling, GitOps delivery, and full observability.

---

## Overview

This repository contains the complete infrastructure, configuration, and tooling for a cloud-native platform running on AWS EKS. It follows the Gruntwork Reference Architecture pattern with Terragrunt for multi-account, multi-region infrastructure management, ArgoCD for GitOps application delivery, and Kargo for progressive promotion.

### Key Capabilities

- **Multi-Account AWS Organization** — Management, network, non-prod, prod, and DR accounts with SCPs, SSO, and GuardDuty
- **Multi-Region Deployment** — 4 EU regions (eu-central-1, eu-west-1, eu-west-2, eu-west-3) per environment
- **EKS with Karpenter** — Autoscaling with per-environment node pool profiles (x86, ARM64/Graviton, spot/on-demand)
- **Event-Driven Scaling** — KEDA, HPA defaults, and Watermark Pod Autoscaler support
- **Transit Gateway Networking** — Centralized connectivity with route table isolation (prod/nonprod/shared)
- **GitOps Pipeline** — ArgoCD ApplicationSets with Kargo progressive delivery
- **Observability** — Prometheus, Grafana, Loki, Tempo, OpenTelemetry, Pyroscope
- **Security** — OPA/Gatekeeper, network policies, External Secrets Operator, Checkov scanning
- **DNS Failover** — Custom Go controllers for DNS monitoring and automated failover

---

## Architecture

### AWS Multi-Account Organization

```
Management Account (_org)
├── Security OU
├── Infrastructure OU
│   └── Network Account — Transit Gateway, VPN, Route53 Resolver
├── Workloads OU
│   └── NonProd OU
│       ├── Dev Account
│       └── Staging Account
└── Prod OU
    ├── Prod Account
    └── DR Account
```

### Platform Stack (per region)

Each environment/region deploys the following units via Terragrunt stacks:

```
vpc → tgw-attachment → eks → karpenter-iam → karpenter-controller → karpenter-nodepools
                        ├── keda
                        ├── hpa-defaults
                        ├── wpa
                        └── monitoring
secrets → rds
```

### Network Architecture

The network account runs a connectivity stack per region:

```
vpc → transit-gateway → ram-share → tgw-route-tables → vpn-connection → route53-resolver
```

Workload accounts attach to the Transit Gateway via `tgw-attachment` in their platform stack.

---

## Repository Structure

```
platform-design/
├── terraform/modules/              # Terraform modules (22 modules)
│   ├── vpc/                        # VPC with deterministic CIDR allocation
│   ├── eks/                        # EKS cluster (terraform-aws-modules ~> 21.15)
│   ├── karpenter/                  # Karpenter controller (Helm)
│   ├── karpenter-nodepools/        # NodePool + EC2NodeClass CRDs
│   ├── keda/                       # KEDA event-driven autoscaler (Helm)
│   ├── hpa-defaults/               # Platform HPA (CoreDNS)
│   ├── wpa/                        # Datadog Watermark Pod Autoscaler
│   ├── rds/                        # RDS PostgreSQL
│   ├── secrets/                    # AWS Secrets Manager
│   ├── monitoring/                 # Monitoring infrastructure
│   ├── organization/               # AWS Organization + OUs
│   ├── scps/                       # Service Control Policies
│   ├── sso/                        # IAM Identity Center
│   ├── transit-gateway/            # Transit Gateway core
│   ├── tgw-attachment/             # TGW VPC attachments
│   ├── tgw-route-tables/           # TGW route tables
│   ├── ram-share/                  # AWS RAM resource sharing
│   ├── vpn-connection/             # Site-to-site VPN
│   ├── route53-resolver/           # DNS forwarding
│   └── ...
│
├── catalog/                        # Terragrunt catalog (reusable units & stacks)
│   ├── units/                      # 22 units (one per TF module)
│   └── stacks/
│       ├── platform/               # Full platform stack
│       └── connectivity/           # Network connectivity stack
│
├── terragrunt/                     # Live infrastructure configuration
│   ├── root.hcl                    # Root config (S3 backend, providers)
│   ├── _org/                       # Management account (organization, SCPs, SSO, GuardDuty)
│   │   └── _global/
│   ├── network/                    # Network account (Transit Gateway, VPN)
│   │   └── {eu-west-1,...}/connectivity/
│   ├── dev/                        # Dev account
│   │   ├── account.hcl             # Env-specific vars + scaling profiles
│   │   └── {eu-west-1,...}/platform/
│   ├── staging/                    # Staging account
│   ├── prod/                       # Production account
│   └── dr/                         # Disaster recovery account
│
├── apps/                           # Application definitions (Helm values)
│   ├── chains/                     # Blockchain/chain services
│   ├── direct/                     # Direct routing services
│   ├── listeners/                  # Event listener services
│   ├── mono/                       # Monolithic services
│   ├── protocols/                  # Protocol services
│   └── infra/                      # Platform infrastructure apps
│       ├── aws-lb-controller/
│       ├── cert-manager/
│       ├── external-secrets/
│       ├── gatekeeper/
│       ├── kargo/
│       ├── velero/
│       └── observability/          # Grafana, Loki, Prometheus, Tempo, OTEL, Pyroscope
│
├── argocd/                         # ArgoCD GitOps configuration
│   ├── applicationset.yaml         # Workload ApplicationSet
│   ├── appproject-workloads.yaml   # AppProject definition
│   ├── kargo-bootstrap.yaml        # Kargo bootstrap
│   └── workloads/                  # Per-team workload configs
│
├── kargo/                          # Kargo progressive delivery
│   ├── analysis-templates/
│   ├── projects/
│   ├── stages/                     # Per-team stage definitions
│   └── warehouses/
│
├── helm/app/                       # Generic application Helm chart
│
├── dns-monitor/                    # Go — DNS health monitoring daemon
├── failover-controller/            # Go — Failover orchestration with state machine
├── dns-sync/                       # DNS zone synchronization
├── services/                       # Reference services
│   ├── example-api/
│   └── hello-world/
│
├── k8s/                            # Kubernetes deployment manifests
│   ├── dns-monitor/
│   ├── dns-sync/
│   ├── failover-controller/
│   └── monitoring/                 # ServiceMonitor + PrometheusRules
│
├── kubernetes/                     # Kubernetes configurations
│   ├── deployments/                # x86/Graviton examples
│   ├── karpenter/                  # NodePool/provisioner configs
│   └── security/                   # RBAC and security policies
│
├── network-policies/               # K8s NetworkPolicy manifests
├── monitoring/dashboards/          # Grafana dashboard JSON
├── checkov-policies/               # Custom AWS Well-Architected checks
├── database/migrations/            # SQL schema migrations
├── envs/                           # Per-env Helm/Kustomize value overrides
├── scripts/                        # Deploy, validate, preflight, cleanup
├── tests/                          # Python E2E + integration tests
├── tools/dns-admin/                # DNS administration utility
│
├── .github/workflows/              # CI pipelines (9 workflows)
├── docs/                           # Architecture documentation
└── CHANGELOG.md
```

---

## Technical Stack

| Category | Components |
|----------|-----------|
| **Cloud** | AWS (EKS, EC2, RDS, S3, Transit Gateway, RAM, SSO, GuardDuty, Organizations) |
| **IaC** | Terraform >= 1.11, Terragrunt >= 0.68, AWS Provider ~> 6.0 |
| **Kubernetes** | EKS 1.34, Karpenter, KEDA, Cilium CNI |
| **GitOps** | ArgoCD (ApplicationSets), Kargo (progressive delivery) |
| **Observability** | Prometheus, Grafana, Loki, Tempo, OpenTelemetry, Pyroscope |
| **Security** | OPA/Gatekeeper, External Secrets Operator, Cert-Manager, Velero, Network Policies |
| **Languages** | Go (controllers), Python (tests), HCL (infrastructure), Bash (scripts) |
| **Data** | PostgreSQL (RDS), Kafka, Redis, InfluxDB |
| **CI/CD** | GitHub Actions (9 workflows), Checkov, Gitleaks, ShellCheck, kubeconform |
| **DNS** | Cloudflare, Route53, custom failover controllers |

---

## CI/CD Pipelines

All pipelines run on push to `main` and on pull requests. Each also triggers when its own workflow file changes.

| Workflow | What it validates |
|---------|------------------|
| **Terraform Validate** | `terraform fmt -check` + `terraform validate` for all 22 modules (matrix) |
| **Terragrunt Validate** | `terragrunt hclfmt --check` + HCL brace-balance syntax check |
| **Helm Chart Validation** | `helm template` + kubeconform against K8s 1.32 schemas |
| **K8s Manifest Validation** | kubeconform for k8s/, kubernetes/, network-policies/, argocd/ |
| **YAML Lint** | yamllint across all YAML (Helm templates excluded) |
| **Well-Architected Compliance** | Checkov security scan on Terraform modules |
| **Secret Scan** | Gitleaks secret detection with full history |
| **ShellCheck** | Shell script linting (severity: error) |
| **Go CI** | `go build` + `go test` for dns-monitor, failover-controller, hello-world |

---

## Environments

| Environment | AWS Account | Purpose | Karpenter Profile |
|-------------|------------|---------|-------------------|
| **_org** | Management | AWS Organization, SCPs, SSO, GuardDuty | N/A |
| **network** | Network | Transit Gateway, VPN, Route53 Resolver | N/A |
| **dev** | Non-Prod | Development workloads | Small pools, 80-90% spot, 30s consolidation |
| **staging** | Non-Prod | Pre-production validation | Medium pools, 70-85% spot, 60s consolidation |
| **prod** | Production | Production workloads | Large pools, 60-70% spot, 300s consolidation |
| **dr** | DR | Disaster recovery standby | Medium pools, 50% spot, 600s consolidation |

Each workload environment deploys to 4 EU regions: `eu-central-1`, `eu-west-1`, `eu-west-2`, `eu-west-3`.

---

## Getting Started

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.11.0
- Terragrunt >= 0.68.0
- kubectl
- Helm

### Deploy a Platform Stack

```bash
# Deploy dev environment in eu-west-1
cd terragrunt/dev/eu-west-1/platform
terragrunt stack plan
terragrunt stack apply
```

### Deploy Network Connectivity

```bash
# Deploy network account connectivity in eu-west-1
cd terragrunt/network/eu-west-1/connectivity
terragrunt stack plan
terragrunt stack apply
```

### Deploy Organization Resources

```bash
# Deploy AWS Organization, SCPs, SSO (global, run once)
cd terragrunt/_org/_global/organization
terragrunt apply

cd ../scps
terragrunt apply
```

### Connect to Cluster

```bash
aws eks update-kubeconfig --name <cluster-name> --region <region>
kubectl get nodes
```

---

## Documentation

| Document | Description |
|----------|------------|
| [Platform Overview](docs/platform-overview.md) | High-level architecture |
| [Tech Stack](docs/01-tech-stack.md) | Technology decisions |
| [Terragrunt Strategy](docs/02-terragrunt-strategy.md) | Multi-env IaC approach |
| [Scale Patterns](docs/scale-patterns.md) | 1k-5k node scaling design |
| [Observability Architecture](docs/observability-architecture.md) | Monitoring/logging/tracing design |
| [SRE Runbook](docs/sre-runbook.md) | Operational procedures |
| [Runbooks](docs/runbooks/) | DNS failover, DR, sync failure procedures |
| [Terraform README](terraform/README.md) | Module documentation |
| [Terragrunt README](terragrunt/README.md) | Live config documentation |
| [CHANGELOG](CHANGELOG.md) | Version history |

---

## Scale Targets

| Metric | Target |
|--------|--------|
| Kubernetes Nodes | 1,000 - 5,000 |
| Pods | 100,000+ |
| Data Ingest | 100 Gbps+ |
| API Latency | <100ms P99 |
| Node Provisioning | <60 seconds |

---

## License

See [LICENSE](LICENSE) for details.
