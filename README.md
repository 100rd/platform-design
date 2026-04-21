# Platform Design

Transaction analytics platform with ML-based scoring and algorithmic template mining across four transaction-heavy domains, deployed as a three-tier system: edge agents at client venues, UK bare-metal data centres for post-analysis and training, AWS for control plane and GitOps.

> **Roadmap**: [PLAN.md](PLAN.md) — phased build plan.
> **Deep dives**: [docs/transaction-analytics/](docs/transaction-analytics/) — architecture, data plane, ML inference, training, edge deployment, compliance.

---

## Purpose

This platform **analyses transactions; it does not execute them.** Clients run their own trading engines, bidders, insurance exchanges. We ingest their transaction streams, mine algorithmic templates from historical sessions, train small domain-specific models, and ship signed scoring artefacts back to their co-located hardware.

### Domains

| Domain | What we analyse | Workload shape |
|--------|-----------------|----------------|
| **HFT** | Trading session tape (trades, quotes, order book deltas) | Real-time scoring at edge (<20 ms), template mining end-of-day in UK |
| **Solana** | On-chain transactions, program calls, MEV patterns | Near-real-time scoring (<30 ms), batch analysis on account state snapshots |
| **Insurance exchange** | Quote/policy documents (PDF, XLS, JSON, XML) flowing through a contract marketplace | Document extraction + scoring at the exchange, template mining in UK |
| **RTB** | Bid requests and wins against an OpenRTB-style exchange | Sub-20 ms scoring at edge, aggregate analysis end-of-day in UK |

See [docs/transaction-analytics/00-domains.md](docs/transaction-analytics/00-domains.md) for per-domain data contracts and SLAs.

### Deployment Tiers

```
┌───────────────────────── Edge (client co-lo, UK + EU) ─────────────────────────┐
│  Real-time scoring agent — signed OCI image or raw binary                       │
│  TRT-LLM engine (Qwen 2.5 3B + LoRA)  +  Triton (XGBoost)  +  templates bundle  │
│  Redis hot feature cache                                                        │
│  Outbound: Kafka producer → telemetry reverse topic                             │
└──────────┬──────────────────────────────────────────────────────────────────────┘
           │ Kafka (transactions in) / Kafka (telemetry + heartbeat out)
           ▼
┌──────────────── UK bare-metal data centres (primary + standby) ────────────────┐
│  Talos Linux + Cluster API + Ansible (low-level config)                         │
│  GPU fleet: H100 (training) + H200 (batch inference, LLM-as-judge)              │
│  QuestDB (tick hot store)  ·  Iceberg on MinIO (cold archive)                   │
│  DuckDB / Trino (batch template mining)  ·  Qdrant (vector similarity)          │
│  Postgres (template + model registry, label store)                              │
│  Argilla (expert feedback UI for traders / scoring engineers)                   │
│  Airflow (training DAGs, event-triggered at 100k accumulated samples)           │
│  Multi-tenancy: namespace-per-tenant + NetworkPolicy + tenant-scoped encryption │
└──────────┬──────────────────────────────────────────────────────────────────────┘
           │ Artefact pull (signed OCI + binary + templates manifest)
           ▼
┌──────────────────────── AWS control plane (existing) ───────────────────────────┐
│  EKS + Karpenter (multi-region eu-central-1, eu-west-1/2/3)                     │
│  ArgoCD + Kargo (GitOps + progressive delivery)                                 │
│  Observability stack (Prometheus, Grafana, Loki, Tempo, OTel, Pyroscope)        │
│  LiteLLM gateway (multi-model serving, fallback, per-team auth)                 │
│  Model registry, CI/CD (GitHub Actions → signed OCI publish)                    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

See [docs/transaction-analytics/01-architecture.md](docs/transaction-analytics/01-architecture.md) for the full tier breakdown.

---

## Overview

This repository contains the infrastructure, configuration, and tooling for the platform. It follows the Gruntwork Reference Architecture pattern for the AWS control plane (Terragrunt, multi-account, multi-region), extends to bare-metal via Talos + Cluster API for the UK DCs, and packages edge agents as signed OCI images plus raw-binary fallback.

### Key Capabilities

**Transaction analytics layer**
- **Domain-specific scoring** — Qwen 2.5 3B base + per-domain LoRA adapters served via vLLM multi-LoRA; XGBoost/LightGBM via Triton FIL for pure numeric features
- **Low-latency edge inference** — TRT-LLM engines with fp8 quantization + speculative decoding, <15 ms TTFT target on H200
- **Template mining** — Event-triggered retraining (threshold 100k accumulated samples per domain) on H100 cluster, output is a signed templates bundle shipped to edge
- **Expert feedback loop** — Argilla UI for traders/scoring engineers to flag suspicious transactions; labels feed Airflow retraining DAGs
- **LLM-as-judge eval** — Multi-model debate (teacher vs student vs independent judge) before new adapter is promoted to edge

**Infrastructure layer**
- **Multi-Account AWS Organization** — Management, network, non-prod, prod, and DR accounts with SCPs, SSO, and GuardDuty
- **Multi-Region Deployment** — 4 EU regions (eu-central-1, eu-west-1, eu-west-2, eu-west-3) for the AWS control plane
- **UK bare-metal** — Two Talos-managed clusters (primary + standby), Cluster API lifecycle, Ansible for firmware/NIC/kernel tuning
- **EKS with Karpenter** — Autoscaling with per-environment node pool profiles (x86, ARM64/Graviton, spot/on-demand)
- **GPU inference cluster** — p5.48xlarge (H100 SXM5), NVSwitch, WireGuard transparent encryption, NCCL > 400 GB/s, Volcano gang scheduling, DRA for fine-grained device allocation
- **Event-Driven Scaling** — KEDA, HPA defaults, Watermark Pod Autoscaler
- **GitOps Pipeline** — ArgoCD ApplicationSets with Kargo progressive delivery (extended to edge rollouts)
- **Observability** — Prometheus, Grafana, Loki, Tempo, OpenTelemetry, Pyroscope; DCGM for GPU; Kafka reverse-topic telemetry from edge
- **Security** — OPA/Gatekeeper, network policies, External Secrets Operator, Checkov scanning, Cilium WireGuard; SOC2-aligned (no PCI-DSS scope — no cardholder data processed)
- **DNS Failover** — Custom Go controllers for DNS monitoring and automated failover

> **Related products (not in this repo)**: *Omniscience* — an internal-engineer-facing platform intelligence / RAG product that reuses the LLM serving infrastructure here. Tracked separately.

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
| **Bare-metal** | Talos Linux, Cluster API, Ansible (firmware / NIC / kernel tuning), MinIO (Iceberg backing store) |
| **IaC** | Terraform >= 1.11, Terragrunt >= 0.68, AWS Provider ~> 6.0, Cluster API providers |
| **Kubernetes** | EKS 1.34 (AWS), Talos-managed k8s (UK), Karpenter, KEDA, Cilium CNI, Volcano gang scheduling, DRA |
| **GitOps** | ArgoCD (ApplicationSets), Kargo (progressive delivery, extended to edge rollouts) |
| **Observability** | Prometheus, Grafana, Loki, Tempo, OpenTelemetry, Pyroscope, DCGM (GPU); Kafka reverse-topic for edge telemetry |
| **Security** | OPA/Gatekeeper, External Secrets Operator, Cert-Manager, Velero, Network Policies, Cilium WireGuard, Cosign (OCI signing) |
| **Languages** | Go (controllers, edge binary), Python (training, tests), HCL (infrastructure), Bash (scripts), Rust (hot-path scoring components where applicable) |
| **Data** | Kafka (ingestion + back-channel), QuestDB (tick hot store), Apache Iceberg on MinIO (cold archive), DuckDB / Trino (batch template mining), PostgreSQL / RDS (state, registry, labels), Redis (edge feature cache), Qdrant (vector similarity) |
| **ML / Inference** | Qwen 2.5 3B base, LoRA adapters, vLLM (multi-LoRA serving), NVIDIA TensorRT-LLM (edge), Triton Inference Server (XGBoost/LightGBM via FIL), LiteLLM (gateway), Argilla (label / feedback UI), Airflow (training DAGs) |
| **CI/CD** | GitHub Actions (9 workflows), Checkov, Gitleaks, ShellCheck, kubeconform, Cosign for artefact signing |
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
| [**Roadmap (PLAN.md)**](PLAN.md) | **Phased build plan for the transaction analytics layer** |
| [**Transaction analytics docs**](docs/transaction-analytics/) | **Architecture, data plane, ML, training, edge, UK DCs, compliance** |
| [Domains](docs/transaction-analytics/00-domains.md) | HFT, Solana, insurance exchange, RTB — data contracts and SLAs |
| [Three-tier architecture](docs/transaction-analytics/01-architecture.md) | Edge / UK bare-metal / AWS control plane |
| [Data plane](docs/transaction-analytics/02-data-plane.md) | Kafka, QuestDB, Iceberg, Redis, Postgres, Qdrant |
| [ML inference](docs/transaction-analytics/03-ml-inference.md) | Qwen 2.5 3B + LoRA, TRT-LLM, vLLM, Triton |
| [Training pipeline](docs/transaction-analytics/04-training-pipeline.md) | Labels, retraining triggers, LLM-as-judge |
| [Edge deployment](docs/transaction-analytics/05-edge-deployment.md) | OCI + raw binary, Kafka back-channel, signed rollouts |
| [UK data centres](docs/transaction-analytics/06-uk-datacenters.md) | Talos, Cluster API, Ansible, multi-tenancy, DR |
| [Compliance & security](docs/transaction-analytics/07-compliance-security.md) | SOC2 mapping, tenant isolation, PCI-DSS out of scope |
| [Platform Overview](docs/platform-overview.md) | High-level infra architecture |
| [Tech Stack](docs/01-tech-stack.md) | Technology decisions |
| [Terragrunt Strategy](docs/02-terragrunt-strategy.md) | Multi-env IaC approach |
| [Scale Patterns](docs/scale-patterns.md) | 1k-5k node scaling design |
| [Observability Architecture](docs/observability-architecture.md) | Monitoring/logging/tracing design |
| [GPU Inference Definition of Done](docs/gpu-inference-dod.md) | Acceptance criteria for GPU cluster |
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
