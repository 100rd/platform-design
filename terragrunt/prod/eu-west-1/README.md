# prod / eu-west-1

Production region deployment in **eu-west-1** (Ireland) across three availability zones (`eu-west-1a`, `eu-west-1b`, `eu-west-1c`).

## Stacks

### Platform (`platform/`)

General-purpose EKS platform cluster for application workloads.

| Unit | Purpose |
|------|---------|
| `vpc` | Platform VPC with public, private, and intra subnets; VPC Flow Logs (365-day retention) |
| `tgw-attachment` | Transit Gateway VPC attachment for cross-account connectivity |
| `secrets` | KMS keys and Secrets Manager resources |
| `eks` | EKS 1.32 cluster with KMS envelope encryption, Bottlerocket managed node groups (m6i.2xlarge, 3-10 nodes) |
| `cilium` | Cilium CNI with ENI prefix delegation, WireGuard encryption, Hubble observability, ClusterMesh |
| `karpenter-iam` | IAM roles and instance profiles for Karpenter |
| `karpenter-controller` | Karpenter v1 controller deployment |
| `karpenter-nodepools` | Multi-architecture node pools: x86, arm64, c-series, PCI-DSS CDE (dedicated on-demand, tainted) |
| `keda` | KEDA event-driven autoscaler (3 operator replicas, 3 metrics server replicas) |
| `hpa-defaults` | Default HPA policies for platform workloads |
| `wpa` | Weighted Pod Autoscaler (disabled in prod) |
| `rds` | RDS PostgreSQL (db.r6g.xlarge, 100 GB, Multi-AZ) |
| `monitoring` | Monitoring stack (3 replicas) |
| `gpu-inference-crossplane` | Crossplane v2.2 hub for GPU node lifecycle management |
| `gpu-inference-argocd` | ArgoCD project and ApplicationSet for GPU inference GitOps |

### GPU Inference (`gpu-inference/`)

Dedicated EKS cluster for large-scale GPU inference workloads. Designed for up to **5,000 nodes** with NVIDIA H100 SXM5 GPUs (p5.48xlarge).

| Unit | Phase | Purpose |
|------|-------|---------|
| `gpu-inference-vpc` | Foundation | Dedicated VPC (10.180.0.0/16) with BGP-ready subnets and TGW Connect attachment |
| `gpu-inference-eks` | Foundation | EKS 1.35 with DRA (Dynamic Resource Allocation), self-managed GPU node groups |
| `gpu-inference-node-tuning` | Foundation | CPU pinning (cores 4-191 isolated), 1536x 2Mi HugePages, NUMA topology for p5.48xlarge |
| `gpu-inference-cilium` | Network | Cilium v1.19 native routing, cluster-pool IPAM (100.64.0.0/10), BGP Control Plane for TGW Connect peering |
| `gpu-inference-cilium-encryption` | Network | WireGuard transparent pod-to-pod encryption, NCCL traffic exclusion, high-scale operator tuning |
| `gpu-inference-tgw-connect` | Network | Transit Gateway Connect GRE tunnels with BGP peers (ASN 65100) for Pod CIDR route advertisement |
| `gpu-inference-gpu-operator` | GPU | NVIDIA GPU Operator v26.3 with DRA driver, CDI, GPU Feature Discovery, NFD |
| `gpu-inference-dra` | GPU | DeviceClass definitions (H100-SXM5, A100-80GB) and ResourceClaimTemplates (single GPU, full 8-GPU node) |
| `gpu-inference-kata-cc` | GPU | Kata Containers v3.22 RuntimeClass for GPU Confidential Computing with attestation |
| `gpu-inference-volcano` | Scheduling | Volcano v1.8 batch scheduler with gang scheduling, bin-packing (GPU weight 10), DRA plugin |
| `gpu-inference-scheduling-policies` | Scheduling | PriorityClass hierarchy (system-critical > training > inference > batch), per-namespace GPU quotas |
| `gpu-inference-victoriametrics` | Observability | VictoriaMetrics cluster mode (vminsert/vmselect/vmstorage) replacing Prometheus for high-cardinality GPU metrics |
| `gpu-inference-dcgm` | Observability | NVIDIA DCGM Exporter v4.5 with XID error detection, temperature alerts, and automatic node tainting |
| `gpu-inference-logging` | Observability | Vector v0.54 DaemonSet shipping GPU logs to ClickHouse v26.3 (3-replica cluster) |
| `gpu-inference-vllm` | Inference | vLLM v0.19 deployment with DRA-based GPU allocation, tensor parallelism (8x H100), Multi-LoRA support |
| `gpu-inference-hpa` | Inference | Custom HPA via Prometheus Adapter scaling on vLLM queue depth and GPU cache utilization |
| `gpu-inference-validation` | Validation | Automated test suite: NCCL benchmarks, network latency, DRA scheduling, security audit, inference throughput |

## Architecture

### Platform Stack

```mermaid
graph TD
    subgraph "Platform VPC"
        VPC[VPC<br/>Public / Private / Intra subnets<br/>Flow Logs 365d]
        TGW[TGW Attachment<br/>Cross-account connectivity]
        RDS[(RDS PostgreSQL<br/>db.r6g.xlarge Multi-AZ)]
    end

    subgraph "Platform EKS 1.32"
        EKS[EKS Control Plane<br/>KMS encryption, Bottlerocket]

        subgraph "CNI & Service Mesh"
            CILIUM[Cilium<br/>ENI prefix delegation<br/>WireGuard + Hubble + ClusterMesh]
        end

        subgraph "Autoscaling"
            KARP[Karpenter<br/>IAM + Controller + NodePools]
            KEDA[KEDA<br/>Event-driven autoscaling]
            HPA[HPA Defaults]
        end

        subgraph "Node Pools"
            X86[x86 pool<br/>m6i/m6a/m5 — 70% spot]
            ARM[arm64 pool<br/>m6g/m7g/c6g — 70% spot]
            CDE[PCI-DSS CDE pool<br/>On-demand only, tainted]
        end

        MON[Monitoring<br/>3 replicas]
        SEC[Secrets<br/>KMS + Secrets Manager]
    end

    subgraph "GPU Inference GitOps"
        XP[Crossplane v2.2<br/>Hub-and-Spoke GPU node lifecycle]
        ARGO[ArgoCD<br/>GPU inference ApplicationSet]
    end

    VPC --> EKS
    VPC --> TGW
    VPC --> RDS
    EKS --> CILIUM
    EKS --> KARP
    KARP --> X86
    KARP --> ARM
    KARP --> CDE
    EKS --> KEDA
    EKS --> HPA
    EKS --> MON
    EKS --> SEC
    EKS --> XP
    EKS --> ARGO

    style CDE fill:#f9e0e0,stroke:#c0392b
    style CILIUM fill:#e0f0e0,stroke:#27ae60
    style EKS fill:#e0e8f0,stroke:#2980b9
```

### GPU Inference Stack

```mermaid
graph TD
    subgraph "Phase 1 — Foundation"
        GVPC[GPU VPC<br/>10.180.0.0/16<br/>BGP-ready subnets]
        GEKS[EKS 1.35<br/>DRA enabled<br/>Self-managed GPU nodes]
        TUNE[Node Tuning<br/>CPU pinning 4-191<br/>1536x HugePages<br/>NUMA topology]
    end

    subgraph "Phase 2 — Network"
        GCIL[Cilium v1.19<br/>Native routing<br/>Cluster-pool IPAM 100.64.0.0/10<br/>BGP Control Plane]
        WG[WireGuard Encryption<br/>Pod-to-pod<br/>NCCL exclusion]
        TGWC[TGW Connect<br/>GRE + BGP peers<br/>ASN 65100]
    end

    subgraph "Phase 3 — GPU & DRA"
        GPUOP[GPU Operator v26.3<br/>DRA driver + CDI<br/>GFD + NFD]
        DRA[DRA DeviceClass<br/>H100-SXM5 / A100-80GB<br/>ResourceClaimTemplates]
        KATA[Kata CC v3.22<br/>Confidential Computing<br/>GPU attestation]
    end

    subgraph "Phase 4 — Scheduling"
        VOLC[Volcano v1.8<br/>Gang scheduling<br/>Bin-packing DRA plugin]
        SCHED[Scheduling Policies<br/>PriorityClasses<br/>GPU quotas per namespace]
    end

    subgraph "Phase 5 — Observability"
        VM[VictoriaMetrics<br/>Cluster mode<br/>High-cardinality GPU metrics]
        DCGM[DCGM Exporter v4.5<br/>XID errors + temp alerts<br/>Auto-taint unhealthy GPUs]
        LOG[Vector v0.54 + ClickHouse v26.3<br/>GPU log pipeline]
    end

    subgraph "Phase 6 — Inference"
        VLLM[vLLM v0.19<br/>8x H100 tensor parallel<br/>Multi-LoRA + DRA claims]
        GHPA[Custom HPA<br/>Prometheus Adapter<br/>Queue depth + cache usage]
        VAL[Validation Suite<br/>NCCL / latency / DRA<br/>security / throughput]
    end

    GVPC --> GEKS
    GEKS --> TUNE
    GEKS --> GCIL
    GCIL --> WG
    GCIL --> TGWC
    GEKS --> GPUOP
    GPUOP --> DRA
    GPUOP --> KATA
    GEKS --> VOLC
    VOLC --> SCHED
    GEKS --> VM
    VM --> DCGM
    GEKS --> LOG
    DRA --> VLLM
    VOLC --> VLLM
    VLLM --> GHPA
    VM --> GHPA
    VLLM --> VAL
    DCGM --> VAL
    GCIL --> VAL

    style GEKS fill:#e0e8f0,stroke:#2980b9
    style GCIL fill:#e0f0e0,stroke:#27ae60
    style GPUOP fill:#f0e8e0,stroke:#e67e22
    style VLLM fill:#f0e0f0,stroke:#8e44ad
    style VM fill:#e8e0f0,stroke:#6c3483
    style WG fill:#e0f0e0,stroke:#27ae60
    style DRA fill:#f0e8e0,stroke:#e67e22
    style VOLC fill:#f9f0e0,stroke:#f39c12
```

### Cross-Stack Connectivity

```mermaid
graph LR
    subgraph "Platform Stack"
        PEKS[Platform EKS 1.32]
        PXP[Crossplane v2.2]
        PARGO[ArgoCD]
    end

    subgraph "GPU Inference Stack"
        GEKS2[GPU EKS 1.35]
        GVLLM[vLLM Inference]
    end

    subgraph "Network"
        TGW2[Transit Gateway]
    end

    PXP -->|manages GPU node lifecycle| GEKS2
    PARGO -->|GitOps sync| GEKS2
    PEKS ---|TGW Connect + BGP| TGW2
    GEKS2 ---|TGW Connect + BGP<br/>Pod CIDR 100.64.0.0/10| TGW2

    style TGW2 fill:#fdf2e9,stroke:#e67e22
    style GVLLM fill:#f0e0f0,stroke:#8e44ad
```

## Configuration

Environment-specific sizing and feature flags are defined in [`../account.hcl`](../account.hcl). Region-specific values (AZs, region shortcode) are in [`region.hcl`](region.hcl).

## Deployment

```bash
# Plan a specific stack
cd platform/   # or gpu-inference/
terragrunt stack plan

# Apply (CI/CD only — from main branch after PR merge)
terragrunt stack apply
```
