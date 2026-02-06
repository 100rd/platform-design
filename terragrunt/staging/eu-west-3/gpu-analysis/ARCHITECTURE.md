# GPU Video Analysis Cluster — staging/eu-west-3

Real-time video analysis platform for sport game temperature maps. Dedicated EKS cluster in Paris (eu-west-3) with NVIDIA A10G inference GPUs, T4 preprocessing GPUs, and CPU coordination nodes — co-located via placement groups for minimal network latency.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AWS Account: staging (222222222222)                       │
│                              Region: eu-west-3 (Paris)                          │
│                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────┐   │
│  │                    VPC: 10.152.0.0/16 (gpu-analysis)                     │   │
│  │                                                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │               Public Subnets (3 AZs) — NAT + ALB                   │  │   │
│  │  │    10.152.64.0/20  │  10.152.80.0/20  │  10.152.96.0/20           │  │   │
│  │  │       (3a)         │       (3b)        │       (3c)                │  │   │
│  │  │  ┌──────┐ ┌──────┐ ┌──────┐                                       │  │   │
│  │  │  │NAT-1 │ │NAT-2 │ │NAT-3 │  (3 NAT Gateways for HA)             │  │   │
│  │  │  └──────┘ └──────┘ └──────┘                                       │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  │                              │                                            │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │              Private Subnets (3 AZs) — EKS Nodes                   │  │   │
│  │  │    10.152.0.0/20   │  10.152.16.0/20  │  10.152.32.0/20           │  │   │
│  │  │       (3a)         │       (3b)        │       (3c)                │  │   │
│  │  │                                                                     │  │   │
│  │  │  ┌───────────────────────────────────────────────────────────────┐  │  │   │
│  │  │  │        EKS: staging-eu-west-3-gpu-analysis (v1.32)           │  │  │   │
│  │  │  │                  Private endpoint only                        │  │  │   │
│  │  │  │                                                               │  │  │   │
│  │  │  │  ┌─────────────────────────────────────────────────────────┐  │  │  │   │
│  │  │  │  │              Cilium CNI (ENI mode, native routing)      │  │  │  │   │
│  │  │  │  │     WireGuard encryption │ Default-deny │ Hubble UI     │  │  │  │   │
│  │  │  │  │              Bandwidth Manager (GPU QoS)                │  │  │  │   │
│  │  │  │  └─────────────────────────────────────────────────────────┘  │  │  │   │
│  │  │  │                                                               │  │  │   │
│  │  │  │  ┌──────────────────────┐  ┌──────────────────────────────┐  │  │  │   │
│  │  │  │  │  System Node Group   │  │  Karpenter Controller (x2)   │  │  │  │   │
│  │  │  │  │  m6i.large (2-3)     │  │  EKS Pod Identity            │  │  │  │   │
│  │  │  │  │  Bottlerocket         │  │  SQS interruption queue      │  │  │  │   │
│  │  │  │  │  CoreDNS, kube-proxy  │  │  PDB: minAvailable=1         │  │  │  │   │
│  │  │  │  └──────────────────────┘  └──────────────────────────────┘  │  │  │   │
│  │  │  │                                                               │  │  │   │
│  │  │  │  ╔══════════════════════════════════════════════════════════╗  │  │  │   │
│  │  │  │  ║        Placement Group: cluster (eu-west-3a only)       ║  │  │  │   │
│  │  │  │  ║                                                          ║  │  │  │   │
│  │  │  │  ║  ┌──────────────────┐  ┌──────────────────────────────┐ ║  │  │  │   │
│  │  │  │  ║  │  GPU Inference   │  │  GPU Preprocessing           │ ║  │  │  │   │
│  │  │  │  ║  │  ─────────────── │  │  ────────────────────        │ ║  │  │  │   │
│  │  │  │  ║  │  g5 (A10G 24GB)  │  │  g4dn (T4 16GB)             │ ║  │  │  │   │
│  │  │  │  ║  │  100% on-demand  │  │  70% spot / 30% on-demand   │ ║  │  │  │   │
│  │  │  │  ║  │  300Gi gp3 10K   │  │  200Gi gp3 5K IOPS          │ ║  │  │  │   │
│  │  │  │  ║  │  IOPS, 750MB/s   │  │  500MB/s throughput          │ ║  │  │  │   │
│  │  │  │  ║  │  Max: 100 CPU    │  │  Max: 100 CPU, 400Gi         │ ║  │  │  │   │
│  │  │  │  ║  │  Taint: gpu=true │  │  Taint: gpu=true             │ ║  │  │  │   │
│  │  │  │  ║  │  Expire: 60d     │  │  Expire: 30d                 │ ║  │  │  │   │
│  │  │  │  ║  │  No disruption   │  │  Consolidate: 180s            │ ║  │  │  │   │
│  │  │  │  ║  │  during biz hrs  │  │                               │ ║  │  │  │   │
│  │  │  │  ║  └──────────────────┘  └──────────────────────────────┘ ║  │  │  │   │
│  │  │  │  ╚══════════════════════════════════════════════════════════╝  │  │  │   │
│  │  │  │                                                               │  │  │   │
│  │  │  │  ┌────────────────────────────────────────────────────────┐   │  │  │   │
│  │  │  │  │  CPU Coordination (multi-AZ, no placement group)      │   │  │  │   │
│  │  │  │  │  c6i/c6a/m6i.xlarge-2xlarge                           │   │  │  │   │
│  │  │  │  │  80% spot / 20% on-demand                              │   │  │  │   │
│  │  │  │  │  Max: 100 CPU, 200Gi │ Consolidate: 60s (aggressive)  │   │  │  │   │
│  │  │  │  │  No GPU taint — runs API servers, schedulers, etc.     │   │  │  │   │
│  │  │  │  └────────────────────────────────────────────────────────┘   │  │  │   │
│  │  │  └───────────────────────────────────────────────────────────────┘  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                           │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │              Database Subnets (reserved, 3 AZs)                    │  │   │
│  │  │    10.152.112.0/20 │ 10.152.128.0/20 │ 10.152.144.0/20           │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
Video Stream Ingestion
         │
         ▼
┌──────────────────┐     Low-latency     ┌──────────────────────┐
│  GPU Preprocessing│ ──────────────────▶ │  GPU Inference        │
│  (T4 / g4dn)      │  (placement group) │  (A10G / g5)          │
│                    │                    │                        │
│  • Video decode    │                    │  • Temperature map     │
│  • Frame extract   │                    │    model inference     │
│  • Resize/normalize│                    │  • Real-time scoring   │
│  • Batch assembly  │                    │  • Result aggregation  │
└──────────────────┘                     └──────────┬───────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │  CPU Coordination     │
                                          │  (c6i/c6a/m6i)       │
                                          │                        │
                                          │  • API serving         │
                                          │  • Job orchestration   │
                                          │  • Result delivery     │
                                          │  • Monitoring          │
                                          └──────────────────────┘
```

## Deployment Stack (7 units)

```
terragrunt stack apply

  ① gpu-vpc ─────────────────────────────────────────────────────── VPC + subnets
       │
  ② gpu-placement-group ─────────────────────────────────── cluster strategy, AZ-a
       │
  ③ gpu-eks ─────────────────────────────────────── EKS v1.32, private endpoint
       │
       ├── ④ gpu-cilium ─────────────────────────── ENI, WireGuard, default-deny
       │
       └── ⑤ gpu-karpenter-iam ──────────────────── Pod Identity, SQS queue
                │
           ⑥ gpu-karpenter-controller ───────────── Helm v1.8.1, 2 replicas
                │
           ⑦ gpu-karpenter-nodepools ────────────── 3 pools: inference, preproc, cpu
```

## NodePool Comparison

| | GPU Inference | GPU Preprocessing | CPU Coordination |
|---|---|---|---|
| **GPU** | A10G (24GB VRAM) | T4 (16GB VRAM) | None |
| **Instances** | g5.xl-4xl | g4dn.xl-4xl | c6i/c6a/m6i.xl-2xl |
| **Spot %** | 0% (SLA) | 70% (batch) | 80% (stateless) |
| **Storage** | 300Gi, 10K IOPS | 200Gi, 5K IOPS | 50Gi, 3K IOPS |
| **Placement** | cluster, AZ-a | cluster, AZ-a | multi-AZ |
| **Max CPU** | 100 | 100 | 100 |
| **Max Memory** | 400Gi | 400Gi | 200Gi |
| **Consolidation** | WhenEmpty, 5min | WhenEmpty/Underutil, 3min | WhenEmpty/Underutil, 1min |
| **Node Expiry** | 60 days | 30 days | 30 days |
| **Disruption** | 0 nodes biz hours | Default 10% | Default 10% |
| **Taint** | `nvidia.com/gpu=true` | `nvidia.com/gpu=true` | None |

## Security Posture

| Control | Implementation |
|---|---|
| **Network isolation** | Dedicated VPC (10.152.0.0/16), separate from platform and blockchain |
| **Default-deny** | CiliumClusterwideNetworkPolicy blocks all traffic by default |
| **Encryption in transit** | WireGuard transparent pod-to-pod encryption |
| **Encrypted storage** | All EBS volumes encrypted at rest |
| **Private API** | EKS endpoint private-only (no public access) |
| **IAM** | EKS Pod Identity for Karpenter (no static credentials) |
| **Node hardening** | Bottlerocket AMI (minimal OS, immutable root) |
| **Bandwidth QoS** | Cilium bandwidth manager prevents GPU pod network saturation |

## Key Terraform Modules

| Module | Source | Version |
|---|---|---|
| VPC | `terraform-aws-modules/vpc/aws` | 6.6.0 |
| EKS | `terraform-aws-modules/eks/aws` | 21.15.1 |
| Karpenter IAM | `terraform-aws-modules/eks/aws//modules/karpenter` | 21.15.1 |
| Placement Group | `terraform/modules/placement-group` | local |
| Cilium | `terraform/modules/cilium` | local (Helm 1.16.5) |
| Karpenter Controller | `terraform/modules/karpenter` | local (Helm 1.8.1) |
| Karpenter NodePools | `terraform/modules/karpenter-nodepools` | local |

## Network CIDR Plan

| VPC | CIDR | Purpose |
|---|---|---|
| Platform | 10.0.0.0/16 - 10.39.0.0/16 | Main platform workloads |
| Blockchain | 10.100.0.0/16+ | Blockchain clusters |
| **GPU Analysis** | **10.152.0.0/16** | **This cluster** |

## Cost Profile (staging estimate)

| Component | Monthly Est. | Notes |
|---|---|---|
| EKS control plane | ~$73 | Fixed cost |
| System nodes (2x m6i.large) | ~$140 | On-demand |
| NAT Gateways (3x) | ~$100 | HA across AZs |
| GPU inference (g5) | Variable | On-demand, scales to 0 |
| GPU preprocessing (g4dn) | Variable | 70% spot discount |
| CPU coordination | Variable | 80% spot discount |
| **Base cost (idle)** | **~$313/mo** | No GPU nodes running |
