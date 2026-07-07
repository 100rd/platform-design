# SPEC-10 — ML / GPU Workloads (inference serving, model lifecycle, multi-cloud GPU ML)

> Portable reverse-engineering of the platform's ML/GPU workload surface. A senior platform team
> can rebuild the same model-serving stack, GPU capacity strategy, ML CI/CD, and multi-cloud
> pattern for a new client from this document alone. Placeholders follow `SPEC-00-overview.md`.

---

## 1. Scope & non-goals

**Scope.** The workloads the GPU platform exists to run: (a) the **model-serving reference
architecture** — the OpenAI-compatible request path `client → WAF → Gateway API → InferencePool →
Endpoint Picker (EPP) → vLLM pods on DRA-claimed GPUs`; (b) the **GPU capacity strategy** that feeds
it — per-machine-family RDMA fabric, provisioner split, gang-scheduling queues, scale-to-zero; (c)
the **model lifecycle** — Airflow training DAGs → MLflow registry → SBOM+signature → Kargo promotion
→ ArgoCD deploy → drift-driven retrain; (d) the **multi-cloud ML pattern** expressing the same
operating model on GKE (etalon), AWS/EKS, Azure/AKS, and owned bare-metal/Talos, including the
Azure two-AKS cross-region federation and its three CI/CD pipelines; (e) **client-adaptation knobs**
(GPU SKUs, model sizes, tensor-parallelism, latency/criticality tiers).

**Non-goals.** This spec does not re-derive: the GPU-cluster **day-2 infra install** (NVIDIA GPU
Operator, DCGM exporter, Volcano, DRA driver), the **node lifecycle / Karpenter / bare-metal
re-imaging** capacity plane, and the **Cilium CNI + Gateway-API data-plane install** — all
→ **SPEC-03 (Compute / Kubernetes)**; **cross-region DNS/failover, VPC/VNet peering & cross-cluster
connectivity** → **SPEC-02 (Network & DNS)**; the **ArgoCD app-of-apps bootstrap + Kargo machinery**
→ **SPEC-04 (Delivery & GitOps)**; the **ADR-0028 tagging taxonomy + Terraform/Terragrunt module &
state conventions** → **SPEC-01 (Foundation/IaC)**; the **metrics/alerting backends**
(VictoriaMetrics/Prometheus/Thanos/Grafana/Alertmanager) → **SPEC-07 (Observability)**; **supply-chain
signing, secrets, and pod identity** → **SPEC-05 (Security)**. This spec references those by contract,
not content, and covers only the ML-specific knobs on each.

**Status of the estate.** Every ML/GPU ADR (0036–0054) is **Proposed / plan-and-validate-only /
apply-gated**: modules default `enabled = false`, workflows are illustrative scaffolds. Rebuild
these as design targets, not as already-wired production.

---

## 2. Architecture

### 2.1 Model-serving reference architecture (the request path)

The serving front is **model-aware and KV-cache-aware**, not an L4 round-robin load balancer. It is
the [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) layered
on whatever Gateway API data plane the cloud provides.

```
                          OpenAI-compatible clients  (POST /v1/chat/completions {"model": "..."})
                                       │
                              ┌────────▼─────────┐   WAF / DDoS / rate-limit / TLS
                              │   WAF layer      │   AWS WAF · Cloud Armor · Azure App-GW WAF · on-prem WAF
                              └────────┬─────────┘
                              ┌────────▼─────────┐   Gateway API data plane (per cloud):
                              │  Gateway (L7)    │   Envoy Gateway (AWS default) · GKE Inference Gateway ·
                              │  GatewayClass    │   App Gateway for Containers (Azure) · Cilium/Envoy (bare-metal)
                              └────────┬─────────┘
                              ┌────────▼─────────┐   Body-Based Router: reads body {"model":X} → header
                              │   HTTPRoute      │   host/path + model-header match → backendRef=InferencePool
                              └────────┬─────────┘
                    ┌──────────────────▼───────────────────┐
                    │  InferencePool  (set of replicas that │   spec.selector {app: vllm}
                    │  share one accelerator + base model)  │   spec.targetPortNumber: 8000
                    │  spec.extensionRef → <pool>-epp       │   spec.extensionRef → EPP service
                    └──────────────────┬───────────────────┘
                              ┌─────────▼────────┐  ext-proc gRPC :9002. Scores every replica on
                              │ Endpoint Picker  │  KV-cache hit affinity · queue depth · running-req /
                              │ (EPP, ext-proc)  │  GPU+KV util · LoRA-adapter affinity; picks best.
                              └─────────┬────────┘
        InferenceObjective (per model) │  criticality Critical>Standard>Sheddable · poolRef ·
        modelName→targetModels (LoRA)  │  targetModels weights → canary/A-B (v3=90% / v4=10%)
                    ┌──────────────────▼───────────────────┐
                    │  vLLM replicas (3×)  :8000            │  Deployment, schedulerName: volcano,
                    │  DRA GPU claim · TP=8 · LoRA · /dev/shm│  DRA ResourceClaim (not nvidia.com/gpu limits)
                    └───────────────────────────────────────┘  NCCL over RDMA fabric (EFA/IB/RoCE/TCPX)
```

**Data-plane choice is per cloud, the CRD contract is identical** (ADR-0047 frames the decision as
"not *inference gateway yes/no* — yes everywhere — but *which Gateway API data plane* hosts it, and
*which WAF*"):

| Cloud | Data plane | WAF | Source ADR |
|---|---|---|---|
| GCP/GKE | GKE Inference Gateway (managed) + Body-Based Router | Cloud Armor (+ optional Model Armor) | ADR-0042 |
| AWS/EKS | Envoy Gateway (default) · ALB+Gateway API (fallback); **VPC Lattice explicitly NOT the inference front** | AWS WAF (`aws_wafv2_web_acl`) | ADR-0047 |
| Azure/AKS | Application Gateway for Containers (Gateway API) + ALB controller | App Gateway WAF policy (regional OWASP) + Front Door WAF | diagram-only (no ADR) |
| Bare-metal/Talos | Cilium L7 / Envoy Gateway (VIP via Cilium LB-IPAM+BGP, ADR-0051) | on-prem `baremetal-ingress-waf` (Cilium L7 or Envoy) | ADR-0053 |

### 2.2 The inference CRD model and the v1 GA rename (ADR-0042/0047/0053)

Pin CRD group **`inference.networking.k8s.io/v1` (v1 GA)** and `gateway.networking.k8s.io/v1`.

- **`InferencePool`** — the set of model-server replicas sharing one accelerator + base model.
  Graduated to **v1/stable** at GA (optional `InferencePoolImport` for cross-cluster). Attached to
  the gateway via **`HTTPRoute`** (`backendRefs[].group: inference.networking.k8s.io`, `kind:
  InferencePool`). Carries `spec.extensionRef` → the EPP service.
- **`InferenceObjective`** — the per-workload **routing + criticality** object. **Renamed from
  `InferenceModel` (v1alpha2) → `InferenceObjective` at v1 GA.** Maps a public model name →
  `targetModels` in the pool with traffic-split **weights** (canary/A-B) and a **criticality** tier
  (`Critical` > `Standard` > `Sheddable`; sheddable is dropped first under saturation). **Multi-LoRA
  = one `InferenceObjective` per adapter.**
- **`EPP` (Endpoint Picker)** — an Envoy **ext-proc** external processor (a *separate* Deployment +
  Service, **not** installed by the gateway). Routes on real serving signals, not round-robin.

> Migration: follow the project v1alpha2→v1 GA guide. The extension is young (v1 GA but evolving —
> the `InferenceModel`→`InferenceObjective` rename *is* that evolution); the CRD version must be
> pinned (`inferenceExtension.crdVersion: v1.0.0`), never `latest`.

### 2.3 EPP scoring algorithm (why it beats round-robin)

The EPP scores each candidate replica and picks the best (GKE overview + ADR-0047):

1. **Prefix / KV-cache hit affinity** → route to the replica that already holds the prompt prefix →
   lower TTFT (time-to-first-token).
2. **Queue depth** → prefer shorter queues.
3. **Running requests / GPU & KV-cache utilization** → avoid hot replicas.
4. **LoRA-adapter affinity** → route to a replica that already has the adapter loaded.
5. **Tie-break**: least-loaded, then round-robin.

`InferenceObjective` overlays business rules on top: `weights` drive canary/A-B splits; `criticality`
governs shedding order under saturation; per-client rate-limit lives in the WAF.

### 2.4 vLLM serving pod (the workload)

Serving runtime is **vLLM** (`vllm/vllm-openai`, OpenAI-compatible, port 8000), deployed as a
**Deployment** (not StatefulSet), 3 replicas, `RollingUpdate maxUnavailable:1 maxSurge:0`,
`schedulerName: volcano`, priority class `gpu-inference-medium`, Volcano queue
`gpu-inference-default`. **GPU is allocated via DRA `ResourceClaimTemplate`, not `nvidia.com/gpu`
limits** — this is the load-bearing modern choice (see §4). Tensor-parallel across 8 GPUs, LoRA
enabled (`max-loras: 8`), 64Gi `/dev/shm` for NCCL, long `startupProbe` for weight load.

### 2.5 GPU capacity strategy

Three coupled decisions decide GPU capacity: **fabric per machine family**, **provisioner per
workload class**, and **gang-scheduling queues + scale-to-zero**.

**(a) Per-family high-performance fabric.** The NCCL collective fabric is the bottleneck for large
models, and each cloud accelerates GPU networking differently *per machine family*, so a single
fabric config cannot span SKUs. Baseline everywhere: **jumbo frames** + RDMA. Matrix:

| SKU | GCP (ADR-0042) | AWS (ADR-0045) | Bare-metal (ADR-0053) |
|---|---|---|---|
| A100 80GB | `a2-ultragpu` gVNIC ~100 Gbps | `p4d`/`p4de` EFA 400 Gbps | A100 pool, IB HDR, MIG-capable |
| H100 80GB | `a3-highgpu-8g` GPUDirect-**TCPX** (4 NICs) ~800 Gbps | `p5` EFAv2 3.2 Tbps | H100 pool, RoCEv2 200/400G, NVLink |
| H100-Mega | `a3-megagpu-8g` GPUDirect-**TCPXO** (8 NICs) ~1.8 Tbps | — | — |
| H200 141GB | `a3-ultragpu-8g` RoCE via **DRANET** 3.2 Tbps | `p5en` EFAv3 3.2 Tbps | H200 pool, IB NDR + SHARP |
| B200 | `a4-highgpu-8g` RoCE via DRANET 3.2 Tbps | `p6`/P6-B200 EFA 3.2 Tbps | — |
| cheap inference | — | `g6e`/`g5` (L40S) | L40S pool 48GB |

MTU: GCP 8896, AWS 9001 (VPC max), bare-metal 9000. **Acceptance gate for any fabric: an NCCL
all-reduce bandwidth test (`nccl-tests`) at the family's line rate** (e.g. ~450 GB/s H100 NVLink).

**(b) Provisioner per workload class (AWS, ADR-0045/0046).** The **EFA DRA driver is NOT supported
with Karpenter or EKS Auto Mode.** This forces a split, not a cluster-wide either/or:

- **Karpenter (default)** GPU pools → EFA via **device plugin** (`vpc.amazonaws.com/efa`); serving +
  bursty training; spot-first + scale-to-zero + consolidation.
- **EKS managed node groups (reserved)** → EFA via **DRA driver** (topology-aware `netdev`
  ResourceClaim composed with the GPU claim under Volcano); large reserved distributed training.
- **EFA training is never spot** (a spot reclaim kills the gang). Scarce SKUs via **EC2 Capacity
  Blocks for ML**. No EKS Auto Mode for GPU pools. (Capacity plane details → SPEC-03.)

**(c) Gang scheduling + queues.** **Volcano (not Kueue)** — Kueue does not do native gang
scheduling. Queues carry weights and GPU caps (e.g. `gpu-inference` weight 10 / cap 64 GPU;
`gpu-training` weight 5 / cap 32). DRA device classes give typed GPU requests. On bare metal there
is **no node autoscaler** — elasticity is *workload* scale-to-zero (KEDA/HPA free GPUs back to the
pool) + Volcano queue reservation + Cluster-API/Sidero re-imaging for physical capacity (ADR-0054).

### 2.6 Model lifecycle (build → registry → promote → serve → monitor)

```
 git push (models/** adapters/**)                     drift breach
        │                                                  │  Alertmanager webhook
        ▼  GitHub Actions (ml-pipeline*.yml)               ▼  → ml-retrain-trigger proxy
 ┌──────────────┐  POST Airflow REST /dags/<dag>/dagRuns   → Airflow REST dagRuns
 │ train (DAG)  │  train_domain_adapter: SFT+LoRA on Qwen 2.5 3B,
 └──────┬───────┘  DeepSpeed ZeRO-3, 8×H100 Volcano gang job
        ▼  poll (40×30s = 20 min bound)
 ┌──────────────┐  eval_adapter_debate — LLM-as-judge debate gate.
 │ eval / gate  │  Quality gate: fail if win_rate < 0.55 OR p95_distance_regression > 0
 └──────┬───────┘
        ▼
 ┌──────────────┐  mlflow models create-version → Staging.  Syft SBOM + cosign keyless (OIDC) sign.
 │ register     │  Artifact store per substrate: GCS · S3 · Azure Blob/ADLS · MinIO/Ceph-RGW.
 └──────┬───────┘
        ▼
 ┌──────────────┐  promote_to_edge: merge LoRA→base · quantize fp8 · compile TRT-LLM engine ·
 │ promote      │  build+sign OCI · register Kargo Freight (dev auto / staging reviewer / prod manual)
 └──────┬───────┘  MLflow Staging→Production on prod promotion (Kargo WebhookPromotion)
        ▼
 ┌──────────────┐  Kargo promotion = argocd-tag-bump opens a PR in the ArgoCD config repo bumping
 │ deploy       │  image.tag + image.digest → ArgoCD syncs → vLLM rollout → InferenceObjective weights
 └──────┬───────┘
        ▼
 ┌──────────────┐  Evidently (drift-exporter Deployment) = accuracy/quality; whylogs (inline) =
 │ monitor      │  feature drift. ServiceMonitor → Prometheus/VM → Alertmanager → PagerDuty + retrain
 └──────────────┘  namespace-per-model isolation (ml-<tenant>-<domain>); metrics prefixed ml_monitoring_
```

Orchestration is **Apache Airflow 2.9 self-hosted (not Kubeflow Pipelines)** — DAGs are already
Airflow DAGs, Airflow is ~2 GiB vs Kubeflow >8 GiB, and the retrain path targets Airflow REST
(ADR-0037). Registry is **MLflow** (`ghcr.io/mlflow/mlflow:v2.21.3`, 2 replicas + PDB) with a
dedicated Postgres backend + object artifact store. Promotion is **Kargo** progressive delivery
(`oci://ghcr.io/akuity/kargo-charts`). Signing is **cosign keyless + Syft SBOM**. GPU training runs
inside the DAGs on Volcano gang jobs — the GitHub Actions jobs themselves are CPU-only control/gate
plane (`ubuntu-latest`).

### 2.7 Multi-cloud ML pattern (one operating model, cloud-native substitutions)

| Layer | GCP (etalon, ADR-0036/0042) | AWS (ADR-0044/0048) | Azure (diagram-only) | Bare-metal (ADR-0049–54) |
|---|---|---|---|---|
| Kubernetes | GKE Standard | EKS (managed CP) | AKS (managed CP) | Talos (self-operated CP) |
| CNI | Cilium/Dataplane V2 | Cilium (ENI/native) | Azure CNI **Powered by Cilium** | Cilium LB-IPAM+BGP |
| GPU day-2 | GPU Operator+DCGM+DRA+**Volcano** | same | same | same (driver-less via Talos ext) |
| Fabric | TCPX/TCPXO / RoCE-DRANET | **EFA** | **InfiniBand** (NDR/HDR) | RoCEv2/IB/SR-IOV+DRANET |
| GPU SKUs | a2/a3/a4 | P5/P4de/G6e | **ND H100 v5 / NDm A100 v4 / NC H100 v5** | H200/H100/A100/L40S |
| Serving | vLLM + GKE IGW | vLLM + Envoy/ALB | vLLM + App-GW for Containers | vLLM + Cilium/Envoy GW |
| Registry | MLflow (Postgres+**GCS**) | MLflow (**RDS+S3**) + SageMaker-adjacent | **Azure ML/MLflow** (Blob/ADLS)+ACR | MLflow (**MinIO/Ceph-RGW**) |
| Image registry | GCP AR | **ECR** (pull-through, cosign) | **ACR** (cosign, geo-replica) | registry + cosign |
| Pod identity | GKE Workload Identity→GSA | **IRSA / EKS Pod Identity**+ABAC | **Entra Workload Identity**→User-Assigned MI | Talos mTLS / K8s SA |
| Parallel FS | GCS + local | **FSx for Lustre** | **Azure Managed Lustre (AMLFS)** | CephFS / Rook-Ceph |
| Elasticity | GKE autoscale+spot+scale-to-zero | **Karpenter**+spot | autoscaler+spot+scale-to-zero | **no autoscaler**; workload scale-to-zero + CAPI re-image |
| Observability | VictoriaMetrics+LGTM | CloudWatch+**AMP/AMG**+ADOT+X-Ray | **Azure Monitor mgd Prometheus**+Log Analytics+App Insights+Mgd Grafana | Prometheus/Thanos+Grafana+Loki/Tempo |
| Multi-region | eu-west9+us-c1, Global LB | 2 regions, **ClusterMesh+Route53/GA+TGW** | **W.Europe+N.Europe, Fleet Mgr+ClusterMesh+Front Door** | 2 UK DCs, GeoDNS, no shared CP |

**Invariants across all clouds.** OpenAI ingress → WAF → Gateway API → InferencePool/EPP/
InferenceObjective → vLLM on DRA GPUs with NCCL over RDMA; three-pipeline CI/CD; MLflow registry +
drift → retrain webhook; ADR-0028 `platform.system/component/owner` tags mandatory; **serving fails
over cross-region but gang-scheduled training/batch is always region/DC-pinned**; secondary region
cost-bounded (scale-to-zero + spot).

### 2.8 Azure two-AKS cross-region federation + three CI/CD pipelines (diagram-only pattern)

Azure has **no ADR or written plan** — the design lives only in the architecture diagram and is a
field-for-field mirror of the AWS diagram. Capture it as a portable pattern:

- **Topology.** Two active AKS clusters — **Region A (West Europe)** primary, pod CIDR
  `10.10.0.0/16`; **Region B (North Europe)** active/standby, pod CIDR `10.20.0.0/16` (non-overlapping,
  ClusterMesh-ready). **Azure Kubernetes Fleet Manager** = multi-cluster L4 LB + resource propagation
  + policy. East-west = **managed Cilium Cluster Mesh** (direct pod-to-pod, no gateways). North-south
  = **Azure Front Door (anycast) + WAF + health-probe A↔B failover**. Backbone = **Global VNet
  peering** (or VNet-to-VNet VPN).
- **Per-region stack (identical A/B).** App Gateway for Containers (Gateway API) + WAF; InferencePool/
  EPP; vLLM on N-series GPU pools over InfiniBand; GPU Operator+DCGM+Volcano+DRA; Entra Workload
  Identity (secretless federated credential → User-Assigned Managed Identity); Azure Monitor managed
  Prometheus + Log Analytics + App Insights + Managed Grafana.
- **GPU pools.** ND H100 v5 (8×H100, NDR IB 3.2 Tbps) training; NDm A100 v4 (8×A100, HDR IB 1.6 Tbps);
  NC H100 v5 (1–2×H100) inference. Spot + scale-to-zero + autoscaler.
- **The three CI/CD pipelines** (GitHub Actions → ACR → Flux/ArgoCD GitOps):
  1. **Backend apps** — build/test/lint → ACR (buildx + cosign) → Defender/Trivy + SBOM → Flux/ArgoCD
     → rolling/canary AKS Deployment.
  2. **ML workers (Airflow/Volcano)** — build worker image (CUDA/torch base) → ACR → Flux syncs
     Airflow DAGs + Volcano Job manifests → Volcano gang-scheduled GPU job → artifacts to MLflow/Blob.
  3. **Inference (model, e.g. Qwen3)** — model-registry trigger → build vLLM serving image (weights
     from Blob/Lustre → ACR) → **eval gate (accuracy/TTFT canary)** → Flux/ArgoCD → vLLM Deployment +
     InferencePool → **canary via App Gateway / Front Door (shadow → % traffic)** → SLO-gated
     promote/auto-rollback.

---

## 3. Decision record

Cite as `ADR-NNNN <title>` (this estate's `docs/adrs/`). All Proposed/apply-gated.

| Decision | Rationale | Trade-off accepted | Source ADR |
|---|---|---|---|
| Serving front = Gateway API Inference Extension (InferencePool/InferenceObjective/EPP), not L4 LB | Model-blind, cache-blind round-robin wastes GPUs; EPP routes on KV-cache + queue + load | EPP is a separate moving part that must be deployed & wired explicitly | ADR-0042, 0047, 0053 |
| Pin CRD `inference.networking.k8s.io/v1` (v1 GA); `InferenceModel`→`InferenceObjective` | Extension reached v1 GA, vLLM-integrated via llm-d; vendor-neutral | Young API still evolving — version must be pinned, migration guide followed | ADR-0047 |
| EPP data plane = Envoy Gateway default on AWS (ALB fallback); VPC Lattice NOT the inference front | The extension's reference data plane is Envoy; EPP is an Envoy ext-proc | Two-data-plane story; WAF-on-Envoy indirection (two hops) | ADR-0047 |
| GPU via DRA `ResourceClaim`, not `nvidia.com/gpu` limits | DRA is the typed, topology-aware modern path; composes GPU + RDMA claims | DRA GA floor (EKS 1.33 / GKE 1.32.1) raises version requirement | ADR-0044, 0036 |
| NVIDIA GPU Operator (not standalone device plugin / managed driver) | The Operator is the only path that unlocks DRA | Sharp driver coupling: double-driver or no-driver failure modes | ADR-0036, 0044, 0050 |
| Gang scheduler = Volcano, not Kueue | Volcano does native gang scheduling; Kueue only approximates it | Extra scheduler to operate alongside default | ADR-0036, 0044 |
| Per-machine-family RDMA fabric (TCPX/TCPXO/RoCE/EFA/IB) with NCCL bandwidth gate | Fabric is the NCCL bottleneck; each family accelerates differently | Per-family node-pool/network complexity; more VPCs | ADR-0042, 0045, 0053 |
| AWS provisioner split: Karpenter default + managed node groups for EFA-DRA training | EFA DRA driver unsupported under Karpenter/Auto Mode | Two provisioners; fabric mode coupled to provisioner | ADR-0045, 0046 |
| EFA training never spot; scarce SKUs via Capacity Blocks | A spot reclaim kills the gang | Capacity Block lifecycle (time-boxed, must renew) | ADR-0046 |
| Orchestrator = self-hosted Airflow 2.9, not Kubeflow Pipelines | DAGs already Airflow; lighter; retrain path targets Airflow REST | Self-hosted Airflow patch/upgrade burden | ADR-0037 |
| Registry = MLflow (dedicated Postgres backend + object artifact store) | Standard registry; Staging→Production stage gates | New DB baseline cost; object-store IAM per cloud | ADR-0037, 0048, 0052 |
| Fold cluster-agnostic ML layer by reference; per-cloud swap only backends | ML layer is cluster-agnostic by design; avoid duplicating ADRs | Cross-ADR coupling; N× backend modules in-repo | ADR-0048 |
| Drift = Evidently (accuracy) + whylogs (feature) → Alertmanager → retrain proxy → Airflow | Platform owns Grafana/Thanos/Alertmanager; needs PromQL-native metrics | Two tools; reference-dataset mgmt; retrain-storm risk | ADR-0038 |
| Promotion = Kargo Freight (dev auto / staging reviewer / prod manual) via ArgoCD tag bump | Progressive delivery with staged gates + GitOps audit trail | Extra controller; PR-bump indirection | ADR-0037, 0021 |
| Sign every artifact: cosign keyless (OIDC) + Syft SBOM | Supply-chain provenance; SOC2 reproducibility invariants | Signing/SBOM step in every pipeline | ADR-0037, 0048 |
| Bare-metal: Talos immutable OS, driver-less Operator (driver via system extension) | No `apt`/DKMS/writable `/usr`; driver change = image change + A/B reboot | Coupled Talos+driver upgrades; inverse-default footgun | ADR-0049, 0050 |
| Bare-metal: no node autoscaler; workload scale-to-zero + CAPI re-image | Autoscaling a finite owned rack is a category error | No fast burst; capacity is capex | ADR-0054 |
| Cross-region: serving fails over (DNS/health), training/batch region-pinned | Gang training can't tolerate cross-region reschedule | No cross-region GPU pooling | ADR-0044, 0043 |

---

## 4. Implementation blueprint

### 4.1 Directory layout (load-bearing paths)

```
apps/infra/                              # Helm charts, ArgoCD-delivered (day-2)
  gpu-operator/         values.yaml + values-gpu-inference.yaml   # NVIDIA GPU Operator (DRA on)
  volcano/              values.yaml                               # gang scheduler + queues (comments)
  dcgm-exporter/        values.yaml                               # GPU health metrics + auto-taint
  aws-eks-inference-gateway/   templates/{inferencepool,inferenceobjective,httproute,endpoint-picker}.yaml
  baremetal-inference-gateway/ values.yaml                        # mirror (values-only)
  mlflow/ mlflow-aws/ mlflow-baremetal/  values.yaml             # registry, one per substrate
  ml-monitoring/        values.yaml + values-{aws,baremetal}.yaml # Evidently/whylogs drift
  airflow/ airflow-baremetal/  dags/*.py                          # orchestrator + training DAGs
  kargo/                                                          # promotion engine
  cilium/               values-gpu-inference.yaml                 # CNI overlay (WireGuard, BGP)
k8s/gpu-inference/                       # raw manifests (the actual serving workload)
  vllm/       deployment.yaml service.yaml configmap.yaml hpa.yaml
  scheduling/ priority-class-*.yaml podgroup-*.yaml
terraform/modules/                       # plan-time twins of the above
  gpu-inference-vllm/ gpu-inference-volcano/ aws-eks-inference-gateway/
  gke-inference-gateway/ aws-ml-artifact-store/ baremetal-ml-artifact-store/ ...
catalog/units/                           # Terragrunt units (thin wrappers)
  gpu-inference-{vllm,volcano,dra,dcgm,gpu-operator,eks,hpa}/ aws-eks-inference-gateway/ ...
  baremetal-ml-monitoring/ ml-artifact-store/
argocd/  applicationset-gpu-inference.yaml   # dedicated ApplicationSet for cluster-type: gpu-inference
.github/workflows/  ml-pipeline.yml  ml-pipeline-aws.yml  ml-pipeline-baremetal.yml
                    ml-monitoring-baremetal-validate.yml
.github/actions/    harden-runner/ syft-sbom/ cosign-sign/ argocd-tag-bump/   # composite actions
docs/architecture/  {azure,aws}/*-ml-stack.excalidraw  baremetal-ml-stack.excalidraw  gcp-ml-*.excalidraw
```

### 4.2 Dedicated GPU-inference ApplicationSet (matrix generator)

The gpu-inference cluster diverges enough (VictoriaMetrics not Prometheus, Cilium native+BGP+
WireGuard, GPU charts) that it gets its **own** ApplicationSet; the standard one excludes it via
`matchExpressions: cluster-type NotIn [gpu-inference]`. Charts get a `values-gpu-inference.yaml`
delta on top of `values.yaml`; `observability/*` is excluded (VictoriaMetrics replaces it).

```yaml
# argocd/applicationset-gpu-inference.yaml (sanitized)
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - git:
              repoURL: git@github.com:{{VCS_ORG}}/platform-design.git
              directories:
                - path: apps/infra/*
                - { path: apps/infra/observability/*, exclude: true }   # VM, not Prometheus
          - clusters:
              selector: { matchLabels: { cluster-type: gpu-inference } }
  template:
    spec:
      source:
        helm:
          ignoreMissingValueFiles: true
          valueFiles: [values.yaml, values-gpu-inference.yaml,
                       '../../../envs/{{ .values.env }}/values/infra/{{ .path.basename }}.yaml']
      syncPolicy: { automated: { prune: true, selfHeal: true },
                    syncOptions: [CreateNamespace=true, ServerSideApply=true] }
```

### 4.3 Serving CRDs (InferencePool + InferenceObjective + EPP)

```yaml
# InferencePool: the replica set sharing one accelerator + base model
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
spec:
  selector: { app: vllm }
  targetPortNumber: 8000
  extensionRef: { name: vllm-pool-epp }        # → the EPP ext-proc service
---
# InferenceObjective: one per model/LoRA; criticality + weights drive shed order & canary
apiVersion: inference.networking.k8s.io/v1
kind: InferenceObjective
spec:
  criticality: Critical                         # Critical > Standard > Sheddable
  poolRef: { name: vllm-pool }
  targetModels: [ { name: fraud-scorer-v3 } ]   # multi-LoRA → multiple objectives
```

**EPP hardening** — the recent fix bounds the ext-proc so it cannot OOM-pressure the node.
Deliberate shape: **CPU request-only (no limit) to avoid throttling latency-sensitive routing;
memory request + hard limit; non-root UID 65534; read-only rootfs; drop ALL caps.**

```yaml
# apps/infra/aws-eks-inference-gateway/values.yaml (EPP block, verbatim shape)
epp:
  image: registry.k8s.io/gateway-api-inference-extension/epp:v1.0.0
  replicas: 2
  resources:
    requests: { cpu: 100m, memory: 128Mi }
    limits:   { memory: 256Mi }                 # memory-only limit (hard cap)
  podSecurityContext:       { runAsNonRoot: true, runAsUser: 65534 }
  containerSecurityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true,
                              capabilities: { drop: [ALL] } }
```
EPP container port 9002 (`grpc-ext-proc`), args `--pool-name` / `--pool-namespace`, env
`INFERENCE_CRD_VERSION`. Terraform twin gates it `count = enabled && deploy_epp`.

### 4.4 vLLM Deployment with DRA GPU claim

```yaml
# k8s/gpu-inference/vllm/deployment.yaml (DRA claim, verbatim shape)
apiVersion: resource.k8s.io/v1beta1
kind: ResourceClaimTemplate
metadata: { name: single-gpu-inference, namespace: gpu-inference }
spec:
  spec:
    devices:
      requests: [ { name: gpu, deviceClassName: gpu.nvidia.com, count: 8 } ]   # TP=8
      config:
        - requests: [gpu]
          opaque:
            driver: gpu.nvidia.com
            parameters: { apiVersion: gpu.nvidia.com/v1alpha1, kind: GpuClaimParameters,
                          sharing: { strategy: None } }
---
# Deployment pod spec (excerpt)
spec:
  schedulerName: volcano
  priorityClassName: gpu-inference-medium
  affinity: { nodeAffinity: { requiredDuringSchedulingIgnoredDuringExecution:
    { nodeSelectorTerms: [ { matchExpressions: [
      { key: gpu-inference, operator: In, values: ["true"] },
      { key: nvidia.com/gpu.product, operator: In, values: ["H100-SXM5"] } ] } ] } } }
  tolerations: [ { key: nvidia.com/gpu, operator: Exists, effect: NoSchedule } ]
  resourceClaims: [ { name: gpu-claim, resourceClaimTemplateName: single-gpu-inference } ]
  containers:
    - name: vllm
      resources:
        requests: { cpu: "16", memory: "128Gi" }
        limits:   { cpu: "32", memory: "256Gi" }
        claims:   [ { name: gpu-claim } ]
```
`configmap.yaml` carries the model config: `tensor-parallel-size: 8`, `max-model-len: 131072`,
`gpu-memory-utilization: 0.92`, `dtype: bfloat16`, `enable-lora: true`, `max-loras: 8`, plus LoRA
adapters. **Replace the `busybox` `model-loader` init container** with a real weight pull (from
object store / Lustre); HF token from optional secret `vllm-secrets/hf-token`. `/dev/shm` = 64Gi
Memory emptyDir for NCCL. Terraform twin also emits a VMServiceScrape keeping `vllm:.+` metrics.

### 4.5 GPU Operator + Volcano knobs

```yaml
# apps/infra/gpu-operator/values.yaml (load-bearing)
driver:    { enabled: false }                   # cloud AMI ships driver; TRUE only on AL2023
toolkit:   { version: "v1.17.5-ubuntu22.04" }
draDriver: { enabled: true }                    # backs the vLLM ResourceClaims
migManager:{ default: all-disabled }            # migStrategy: none (full-GPU); mixed for MIG slices
```
```yaml
# apps/infra/volcano/values.yaml — plugin order is load-bearing
plugins: [gang, dra, predicates, proportion, priority, nodeorder, binpack]
# binpack weighted toward GPU packing: binpack.weight 10, binpack.resources nvidia.com/gpu 10
```
> **Known discrepancy to reconcile:** `gang.enablePreemptable` is `true` in the chart values but
> `false` in `terraform/modules/gpu-inference-volcano/main.tf`. Queue CRDs (`training`/`inference`/
> `batch`) are created in Terraform, not the chart — two sources of truth. Pick one.

### 4.6 ML CI/CD workflow (four-job DAG)

All three variants share the topology `train → eval → register → deploy`, all `ubuntu-latest`
(GPU work is delegated to Airflow inside the cluster). Only auth + registry + artifact store differ.

```yaml
# .github/workflows/ml-pipeline.yml (GKE variant, sanitized skeleton)
on:
  workflow_dispatch: { inputs: { model: {required: true}, environment: {default: dev} } }
  push: { branches: [main], paths: [models/**, adapters/**] }
permissions: { contents: read, id-token: write }        # WIF/OIDC + cosign keyless
concurrency: { group: ml-pipeline-${{ github.ref }}-${{ inputs.model }}, cancel-in-progress: false }
jobs:
  train:    # harden-runner → checkout → cloud auth → POST Airflow /dags/train_domain_adapter/dagRuns
  eval:     # needs train; poll /dagRuns/${RUN_ID} 40×30s (20 min); success→pass failed→fail
  register: # needs eval; mlflow models create-version → Staging; syft-sbom + cosign-sign
  deploy:   # needs register; environment gate; argocd-tag-bump app=mlflow-serving-${MODEL_ID}
```

Per-substrate deltas: **AWS** adds `aws-actions/configure-aws-credentials@v4` +
`amazon-ecr-login@v2`, `ECR_REGISTRY: {{AWS_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com`.
**Bare-metal** drops cloud auth, uses Airflow bearer token + S3 static keys, DAG
`train_domain_adapter_baremetal`, artifact `s3://mlflow-artifacts/${MODEL_ID}/${SHA}` via
`MLFLOW_S3_ENDPOINT_URL` (MinIO/Ceph-RGW), env choices `staging`/`prod` (no `dev`).

```yaml
# ml-monitoring-baremetal-validate.yml — PR gate, NO APPLY (plan/validate only)
env: { HELM_VERSION: 3.17.0, TF_VERSION: 1.14.8, TG_VERSION: 1.0.8 }
jobs: [helm-lint, yamllint, terragrunt-validate, summary]   # helm template + verify ADR-0028 labels
```

Composite `argocd-tag-bump` = the "Kargo promotion" deploy step: opens a PR in the ArgoCD config
repo bumping `image.tag`+`image.digest` (via `yq`), commits as the CI bot, labels `auto-merge` for
non-prod. **Sanitize its defaults:** repo `{{VCS_ORG}}/argocd`, committer `{{ORG}}-platform-ci[bot]`
/ `ci@{{DOMAIN}}`.

### 4.7 MLflow registry per substrate

| Substrate | Backend DB | Artifact store | Pod identity |
|---|---|---|---|
| GKE | Cloud SQL PG16 | `gs://mlflow-artifacts-{env}-{{GCP_PROJECT_ID}}` | Workload Identity SA `mlflow` (`roles/storage.objectAdmin`) |
| AWS | RDS PG | `s3://mlflow-artifacts-{env}-{{AWS_ACCOUNT_ID}}` (versioning, SSE-KMS, lifecycle) | EKS Pod Identity + ABAC (`platform:system=ml-pipeline`) |
| Bare-metal | CloudNativePG (`mlflow-pg-rw`) | `s3://mlflow-artifacts` on MinIO/Ceph-RGW | ESO/Vault Secret `mlflow-s3-credentials` |

Artifact-store lifecycle (AWS): Standard-IA 90d → Glacier IR 365d → expire 730d. Bucket IAM uses
**EKS Pod Identity trust + ABAC** (`aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system`).
All artifact-store modules default `create_resources = false` (apply-gated).

### 4.8 Ordering / dependencies (what must exist before what)

1. **GPU cluster infra** (GPU Operator + DRA driver, DCGM, Volcano, VictoriaMetrics) — via the
   dedicated ApplicationSet — before any vLLM pod can claim a GPU.
2. **Gateway API CRDs + inference-extension CRDs (pinned v1)** + a **GatewayClass** (Envoy/Cilium/
   AppGW/GKE-IGW) before InferencePool/HTTPRoute apply.
3. **EPP Deployment+Service** before the InferencePool `extensionRef` resolves (gateway alone is
   insufficient — ADR-0047 D2).
4. **MLflow (DB + object store + pod identity)** and **Airflow** before any pipeline run.
5. **Kargo project + Freight + ArgoCD config repo** before the `deploy` job's tag bump merges.
6. **WAF web ACL** attached to the fronting LB before exposing the Gateway publicly.

---

## 5. Parameterization table

| Placeholder | Meaning | Default in this estate | Resize guidance |
|---|---|---|---|
| `{{VCS_ORG}}` | Git hosting org | — | your VCS org; owns the platform + GitOps-config repos |
| `{{ORG}}` / `{{DOMAIN}}` | org slug / DNS zone (CI bot email) | — | see SPEC-00 |
| `{{PRIMARY_REGION}}` / `{{DR_REGION}}` | serving + DR regions | GCP eu-west9/us-c1 · AWS us-east-1/us-west-2 · Azure W.Europe/N.Europe | ≥2 regions; training region-pinned |
| `{{AWS_ACCOUNT_ID}}` / `{{GCP_PROJECT_ID}}` / `{{AZURE_SUBSCRIPTION_ID}}` | cloud identity | — | injected via CI `vars.*`, never hardcoded |
| `{{ML_IMAGE_REPO}}` / `{{ECR_REGISTRY}}` | model image registry | `{{AWS_ACCOUNT_ID}}.dkr.ecr.{{PRIMARY_REGION}}.amazonaws.com/ml` | ECR/ACR/AR/registry per cloud |
| `{{MLFLOW_TRACKING_URI}}` / `{{AIRFLOW_BASE_URL}}` / `{{MLFLOW_S3_ENDPOINT_URL}}` | ML control-plane endpoints | CI `vars.*` | per-substrate; bare-metal points at MinIO/Ceph-RGW |
| `{{ARGOCD_CONFIG_REPO}}` / `{{CI_BOT_NAME}}` / `{{CI_BOT_EMAIL}}` | promotion PR target + committer | `{{VCS_ORG}}/argocd` · `{{ORG}}-platform-ci[bot]` · `ci@{{DOMAIN}}` | your GitOps config repo + bot |
| `{{MODEL_ID}}` / `{{BASE_MODEL}}` | served model + base | e.g. `fraud-uk` / Qwen 2.5 3B / Llama-3-70B-Instruct | any HF/local model |

**Sizing knobs** (default → resize):

| Knob | Default | Resize guidance |
|---|---|---|
| GPU SKU / instance family | H100-SXM5 (`p5`/`a3-highgpu-8g`/ND H100 v5) | A100/L40S for cheaper inference; H200/B200 for largest models |
| `tensor-parallel-size` / DRA `count` | 8 | match GPUs per node; smaller models → 1–2 (use `g6e`/NC) |
| vLLM `replicas` | 3 | scale to QPS; HPA/KEDA scale-to-zero on idle |
| `max-model-len` / `gpu-memory-utilization` | 131072 / 0.92 | lower ctx for memory headroom |
| `max-loras` | 8 | per-tenant adapter count |
| EPP `replicas` / resources | 2 / cpu 100m req, mem 128Mi req / 256Mi limit | raise mem limit for very large pools |
| InferenceObjective `criticality` | Critical / Standard / Sheddable | tag latency-critical models Critical |
| WAF `rate_limit` (AWS) | 2000 / 5-min | tune per client SLA |
| Volcano queue caps | inference 64 GPU / training 32 GPU | size to fleet |
| MLflow artifact lifecycle | IA 90d / Glacier 365d / expire 730d | per retention policy |
| Quality gate | `win_rate ≥ 0.55` AND `p95_distance_regression ≤ 0` | tighten per model risk |
| Drift thresholds | dataset_drift warn 0.2/crit 0.4; PSI 0.1/0.25; accuracy 0.85/0.75; F1 0.80/0.65 | per model |

---

## 6. Best practices distilled

1. **Route on serving signals, not connections.** Put an EPP in front of vLLM and score replicas on
   KV-cache/prefix affinity, queue depth, and GPU/KV utilization — a plain L4 LB is model-blind and
   cache-blind and silently wastes accelerator time and TTFT.
2. **Pin the inference CRD version explicitly** (`crdVersion: v1.0.0`, never `latest`). The extension
   is v1 GA but still moving (the `InferenceModel`→`InferenceObjective` rename proves it); an
   unpinned CRD is a self-inflicted outage on the next upstream release.
3. **Deploy the EPP as a first-class object.** Installing the gateway + CRDs is *not* enough — the
   EPP is a separate ext-proc Deployment+Service that must be wired via `InferencePool.extensionRef`.
   Treat "gateway is green but EPP is missing" as a specific failure mode.
4. **Bound the EPP: memory request+limit, CPU request-only.** A hard memory cap stops it
   OOM-pressuring the node; leaving CPU unlimited avoids throttling latency-sensitive routing. Run it
   non-root (UID 65534), read-only rootfs, drop ALL caps.
5. **Allocate GPUs with DRA `ResourceClaimTemplate`, not `nvidia.com/gpu` limits.** DRA is typed and
   topology-aware and composes the GPU claim with an RDMA `netdev` claim — the only clean way to pin
   both accelerator and fabric to a pod.
6. **Make the NCCL all-reduce bandwidth test a hard acceptance gate for every fabric.** A silent
   AMI/NCCL-plugin mismatch degrades EFA/RoCE to TCP with no error; only a measured line-rate
   all-reduce catches it before training runs cost money.
7. **Match the fabric to the machine family, one config per family.** TCPX≠TCPXO≠RoCE≠EFA≠IB; a
   single fabric config cannot span SKUs. Drive selection off a `fabric_mode` node label.
8. **Split the provisioner by workload class on AWS.** Karpenter (serving + bursty, EFA device
   plugin) vs managed node groups (reserved distributed training, EFA-DRA) — because the EFA DRA
   driver is unsupported under Karpenter/Auto Mode. Provisioner is a property of the workload.
9. **Never run gang-scheduled training on spot.** One reclaimed node kills the whole gang; reserve
   scarce SKUs with Capacity Blocks and keep spot for scale-to-zero serving only.
10. **Use Volcano for gang scheduling.** Kueue only approximates it; distributed training needs
    all-or-nothing placement or it deadlocks on partial gangs.
11. **Keep the ML lifecycle layer cluster-agnostic; swap only backends per cloud.** Airflow + MLflow
    + Evidently/whylogs + Kargo + cosign/syft are identical everywhere; only DB, object store, image
    registry, and pod-identity mechanism change. This is what makes multi-cloud tractable.
12. **Gate promotions on an eval, not a green build.** `win_rate ≥ 0.55` and no p95 regression before
    Staging; staged Kargo Freight (dev auto → staging reviewer → prod manual + smoke) before Prod.
13. **Sign and SBOM every model image** (cosign keyless OIDC + Syft) and record reproducibility
    invariants (dataset snapshot id, base-model hash, training-config hash) for SOC2.
14. **Fail serving over cross-region; pin training/batch.** DNS/health failover for the request path;
    never try to reschedule a gang across regions — re-queue it in-region.
15. **Isolate models by namespace** (`ml-<tenant>-<domain>`) with one ServiceMonitor each and
    `platform.system` label filtering, so drift metrics and retrain triggers stay per-tenant.
16. **Secretless pod identity everywhere** — GKE Workload Identity, EKS Pod Identity/IRSA+ABAC, Entra
    Workload Identity federated credential, Talos mTLS. No static cloud keys on serving/training pods.

---

## 7. Known pitfalls

1. **Double-driver / no-driver GPU Operator footgun.** `driver.enabled` must be `false` where the
   node AMI/system-extension already ships the driver (cloud GPU AMIs, Talos extension) and `true`
   only on AL2023-style images. The bare-metal default is the *inverse* of the cloud default — get
   it wrong and you get either a driver conflict or no working GPU driver.
2. **DRA requires the Operator, and a version floor.** DRA needs the GPU Operator (not the managed
   driver) plus EKS ≥1.33 / GKE ≥1.32.1 (DRANET GA raises GKE to `1.35.2-gke.1842000+`). Provisioning
   DRA claims on an older cluster silently fails to schedule.
3. **EFA DRA ≠ Karpenter.** The EFA DRA driver does not work under Karpenter or EKS Auto Mode. Putting
   reserved EFA training on Karpenter pools yields TCP-degraded NCCL, not an error.
4. **Gateway green but EPP absent.** The gateway and CRDs can be healthy while the `extensionRef`
   points at a non-existent EPP; requests then fail model-aware routing. Deploy the EPP explicitly.
5. **As-built divergence — two sources of truth for Volcano.** Chart values and the Terraform module
   disagree on `gang.enablePreemptable` (true vs false) and on where Queue CRDs are created.
   Reconcile to one.
6. **As-built divergence — CI/CD composite-action interface drift.** The scaffold ML workflows call
   `syft-sbom`/`cosign-sign` with `image:` but the actions declare `image-ref:`, and `argocd-tag-bump`
   requires `image-digest`/`values-path`/`bot-token` the workflows don't pass. Treat the workflows as
   illustrative until wired through — do not assume they run end-to-end as-is.
7. **As-built divergence — hardcoded identifiers in scaffold defaults.** The real VCS-org name, the
   CI-bot identity, and the CI-bot email are hardcoded in the `argocd-tag-bump` action defaults, and
   placeholder-shaped tokens (project/account-id strings, well-known test account IDs) appear in
   manifests, actions, and `.tftest.hcl`. A rebuild must scrub and re-parameterize every one before
   sharing — the sanitization rule applies to config defaults, not just copied snippets.
8. **Retrain storms.** A drift breach can fire repeatedly; the retrain proxy must de-dup (15-min) and
   respect a `repeat_interval` (6h) or a flapping model floods the GPU training queue.
9. **`/dev/shm` too small for NCCL.** vLLM tensor-parallel needs a large shared-memory emptyDir
   (64Gi here); the default 64Mi silently kills multi-GPU NCCL init.
10. **Bare-metal kernel-module coupling.** Talos won't mount Ceph RBD until `rbd`+`ceph` are in
    `machine.kernel.modules` (else `csi-rbdplugin` crash-loops), and GPU needs `nvidia*` modules —
    all baked in the immutable image, not installed at runtime.
11. **Azure is undocumented.** The two-AKS federation + three pipelines exist only in an Excalidraw
    diagram with no ADR or plan. Treat §2.8 as the authoritative capture and write the missing ADR.
12. **As-built divergence — `busybox` model-loader stub.** The vLLM init container is a placeholder
    stub; ship a real weight-pull (object store / Lustre) or pods start with no model.

---

## 8. Acceptance checklist

A rebuild passes when:

- [ ] The dedicated `gpu-inference` ApplicationSet syncs GPU charts (GPU Operator w/ DRA, DCGM,
      Volcano, VictoriaMetrics) to `cluster-type: gpu-inference` clusters and the standard
      ApplicationSet excludes them — zero manual steps.
- [ ] `InferencePool`, `InferenceObjective`, and a running EPP (2 replicas, memory-capped, non-root,
      read-only rootfs) exist; CRD group is `inference.networking.k8s.io/v1` pinned to a fixed tag.
- [ ] A `POST /v1/chat/completions {"model":...}` traverses WAF → Gateway → HTTPRoute → InferencePool
      → EPP → a vLLM replica and returns tokens; EPP demonstrably prefers a KV-cache-warm replica.
- [ ] vLLM pods schedule via `volcano`, claim GPUs through a DRA `ResourceClaimTemplate` (not
      `nvidia.com/gpu`), and pass a startup probe under load.
- [ ] An `nccl-tests` all-reduce hits the family's line rate on every GPU pool (no TCP fallback).
- [ ] `ml-pipeline*.yml` runs `train → eval → register → deploy`: Airflow DAG launches a Volcano gang
      job; the eval gate blocks on `win_rate < 0.55` or a p95 regression; MLflow gets a Staging
      version; the image is cosign-signed with an SBOM; Kargo promotes dev→staging→prod.
- [ ] MLflow registry is reachable with the correct per-substrate backend (Cloud SQL / RDS /
      CloudNativePG) and object store (GCS / S3 / MinIO-Ceph) via secretless pod identity.
- [ ] Drift metrics (`ml_monitoring_*`) scrape per model namespace; a synthetic drift breach fires an
      Alertmanager route that (de-duped) POSTs an Airflow retrain `dagRuns`.
- [ ] `ml-monitoring-baremetal-validate.yml` is plan/validate-only (helm lint/template + terragrunt
      validate, no apply) and verifies ADR-0028 `platform.system` labels render.
- [ ] Serving fails over to `{{DR_REGION}}` on health loss; training/batch stays region-pinned.
- [ ] No real account IDs, ARNs, org names, bot emails, or registry hostnames remain — all
      placeholders resolve from SPEC-00 / CI `vars`.

---

## 9. Dependencies on other specs

- **SPEC-01 (Foundation: IaC, Account Topology & State)** — Terraform/Terragrunt module + remote-state
  conventions and account topology the ML modules plug into, plus the ADR-0028
  `platform.system/component/owner` tagging taxonomy that is mandatory on every GPU/ML resource.
- **SPEC-02 (Network Topology & DNS)** — cross-region DNS/failover (Route 53 / Front Door / GeoDNS),
  VPC/VNet peering + Transit Gateway, and Cilium ClusterMesh / Azure Fleet Manager cross-cluster
  east-west, plus the per-family RDMA VPC/fabric plumbing the GPU pools sit on.
- **SPEC-03 (Compute / Kubernetes)** — GPU node pools, Karpenter GPU NodePools, EKS managed node
  groups for EFA-DRA training, Capacity Blocks, bare-metal fixed pools + Cluster-API/Sidero re-image,
  the Cilium CNI + Gateway API **data-plane install**, and the GPU day-2 stack (GPU Operator, DCGM,
  Volcano, DRA). This spec consumes those; SPEC-03 provisions them.
- **SPEC-04 (Delivery & GitOps Machinery)** — ArgoCD app-of-apps, ApplicationSet mechanics, and the
  Kargo project/Freight wiring + the ArgoCD config repo that the `argocd-tag-bump` promotion targets.
- **SPEC-05 (Security)** — cosign keyless + Syft SBOM supply-chain signing, ESO/Vault credential
  materialization, the secretless pod-identity mechanisms per cloud, and the Gatekeeper/Kyverno ML
  policies (`ml-policy`, block-privileged).
- **SPEC-07 (Observability)** — VictoriaMetrics / Prometheus / Thanos / Grafana / Alertmanager that
  DCGM, vLLM, and the drift exporters feed; the retrain-trigger Alertmanager route lives on that
  stack.

> Spec-local placeholders introduced here (`{{VCS_ORG}}`, `{{ML_IMAGE_REPO}}`, `{{ECR_REGISTRY}}`,
> `{{MLFLOW_TRACKING_URI}}`, `{{AIRFLOW_BASE_URL}}`, `{{MLFLOW_S3_ENDPOINT_URL}}`,
> `{{ARGOCD_CONFIG_REPO}}`, `{{CI_BOT_NAME}}`, `{{CI_BOT_EMAIL}}`, `{{GCP_PROJECT_ID}}`,
> `{{AZURE_SUBSCRIPTION_ID}}`, `{{MODEL_ID}}`, `{{BASE_MODEL}}`) should be promoted into
> `SPEC-00-overview.md` if reused by sibling specs.
```
