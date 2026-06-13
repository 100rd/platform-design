# ADR-0042: GPU inference networking & serving uplift on GKE (per-family high-performance fabric: jumbo frames + GPUDirect-TCPX/TCPXO + DRANET/RoCE; GKE Inference Gateway; Cloud Armor)

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — `gcp-gpu-vpc` ships a single VPC with **no
  `mtu`** set (GCP default 1460) and no RDMA/data-plane network; `gcp-gke-gpu-nodepools`
  requests **no gVNIC and no additional node networks**; `gpu-inference-dra` defines
  **GPU-compute** `DeviceClass`/`ResourceClaimTemplate` only (no `netdev`/DRANET);
  `gpu-inference-vllm` exposes a plain **`ClusterIP`** Service (no Gateway API, no
  model-/cache-aware routing); there is **no Cloud Armor** on any inference frontend.
- Date: 2026-06-13
- Authors: platform-team (solution-architect), infra, devops-engineer
- Related issues: extends WS-A "GKE ML infrastructure parity & elasticity" (GCP ML
  Platform plan §4) on the **networking + serving** axis that [ADR-0036](0036-gke-ml-infra-parity-multiregion.md)
  explicitly scoped out; risk-register R1 (multi-region GPU cost), R4 (per-region GPU
  quota/capacity). Motivated by two Google reference architectures requested by the
  platform owner: GKE Inference Gateway "Networking for AI inference", and the GKE +
  DRANET high-performance-fabric codelab.
- Supersedes: (none)
- Superseded by: (none)

## Context

[ADR-0036](0036-gke-ml-infra-parity-multiregion.md) brought the GKE GPU plane to
**compute parity** with EKS — NVIDIA GPU Operator, DCGM, **DRA for GPU compute**,
Volcano gang scheduling, a GCP billing budget, and multi-region topology. It
**deliberately did not touch the data path**: GPU↔GPU network fabric, multi-NIC
pods, GPUDirect/RDMA, or the inference **serving front** (how a request reaches a
vLLM replica). Those are the gaps this ADR closes.

Two forces make this the right next step:

1. **The fabric is the bottleneck for large models.** Tensor- and pipeline-parallel
   serving of large LLMs (and any multi-host inference) is dominated by NCCL
   collective traffic between GPUs. Today the GCP GPU VPC runs at the **default
   1460-byte MTU** with **standard (non-gVNIC) NICs** and **single-NIC pods** — none
   of GCP's GPU-network acceleration is engaged. `terraform/modules/gcp-gpu-vpc/main.tf`
   creates `google_compute_network "this"` with **no `mtu` argument** and a single
   subnet; `gcp-gke-gpu-nodepools` requests no `gvnic` and no `additional_node_network_configs`.

2. **The serving front is naïve.** `gpu-inference-vllm` exposes vLLM through a plain
   `ClusterIP` Service with `sessionAffinity: None`. Requests are spread round-robin
   with **no awareness of model identity, KV-cache locality, or per-replica load**,
   and the inference endpoint has **no WAF/DDoS layer**. The Google "Networking for
   AI inference" architecture's answer to exactly this is the **GKE Inference
   Gateway** (Gateway API + `InferencePool`/`InferenceModel` + Body-Based Router),
   fronted by **Cloud Armor**.

The target accelerator fleet (confirmed by the platform owner) is **mixed: A100,
H100, H200, and B200**. This is the load-bearing fact of this ADR, because **GCP's
GPU-network acceleration differs per machine family** — there is no single fabric
setting that serves all four:

| Accelerator | Machine family | GPU-network acceleration | Pod NIC model | GKE mechanism |
|---|---|---|---|---|
| **A100 80GB** | `a2-ultragpu-*` | **none** (no GPUDirect); up to ~100 Gbps gVNIC | single-NIC | gVNIC + jumbo frames only |
| **H100 80GB** | `a3-highgpu-8g` | **GPUDirect-TCPX** (~800 Gbps, 4 data-plane NICs) | multi-NIC | **legacy GKE multi-networking** (`GKENetworkParamSet` + `Network`) + TCPX NCCL plugin |
| **H100 Mega** | `a3-megagpu-8g` | **GPUDirect-TCPXO** (~1.8 Tbps, 8 data-plane NICs) | multi-NIC | **legacy GKE multi-networking** + TCPXO NCCL plugin |
| **H200 141GB** | `a3-ultragpu-8g` | **GPUDirect RDMA / RoCE** (3.2 Tbps, CX-7) | multi-NIC (RDMA) | **GKE managed DRANET** (DRA for `netdev`) on an RoCE VPC |
| **B200** | `a4-highgpu-8g` | **GPUDirect RDMA / RoCE** (3.2 Tbps, CX-7 Titanium ML) | multi-NIC (RDMA) | **GKE managed DRANET** (DRA for `netdev`) on an RoCE VPC |

Crucially, the two newest families (H200/B200) and the two older H100 families take
**different code paths**: H100/H100-Mega use the *classic* GKE GPU-bandwidth path
(GPUDirect-TCPX/TCPXO over multiple data-plane VPCs, wired with `GKENetworkParamSet`),
whereas A3 Ultra / A4 use **GKE managed DRANET** — the DRA-for-networking driver that
reached **GA on GKE `1.35.2-gke.1842000+`** with hardware support starting at A3 Ultra
(plus A4/A4X, TPU v6e/v7x). DRANET is the **same DRA model already adopted for GPU
compute in ADR-0036**, extended to network devices: a `ResourceClaimTemplate` that
binds RDMA NICs to a pod. So for H200/B200 the fabric becomes a *DRA resource claim*,
composing cleanly with the GPU-compute claims Volcano already schedules.

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (the unified
`platform:system` / `platform.system` taxonomy) is mandatory on every resource
introduced here, exactly as in ADR-0036, so the new networking/serving resources join
the same single-pane `$system` observability and FinOps roll-ups.

## Decision

Add a **per-machine-family high-performance fabric** and a **model-aware serving
front** to the GKE GPU plane, in six plan/validate-only sub-decisions. Nothing here
applies without passing the apply gate. This ADR **extends, and does not re-open,**
ADR-0036 (Operator/DRA-compute/Volcano/DCGM/multi-region) — those decisions stand.

### D1 — Jumbo frames (MTU 8896) + gVNIC as the universal GPU-network baseline

Set **`mtu = 8896`** on every GPU VPC (`gcp-gpu-vpc`) and enable **gVNIC** on every
GPU node pool (`gcp-gke-gpu-nodepools`). This is the **floor for all four families**:

- Larger frames cut packet count on bulk tensor / NCCL transfers; **8896** is the GPU
  fabric MTU GCP documents for GPUDirect and RoCE (the classic GPUDirect-TCPX guidance
  historically used 8244 on the data-plane subnets; **8896 is the safe maximum** and is
  what A3 Ultra / A4 RoCE require).
- **gVNIC is a hard prerequisite** for GPUDirect-TCPX/TCPXO and for RDMA NICs; standard
  VirtIO NICs cannot carry them.
- For **A100**, D1 is the *entire* fabric story (no GPUDirect on `a2`): jumbo frames +
  gVNIC + the existing single-NIC model, no further networking.

This is the smallest, lowest-risk, highest-reach change — one VPC argument + one
node-pool flag, applicable fleet-wide — and is the prerequisite for D2/D3.

### D2 — H100 / H100-Mega: GPUDirect-TCPX/TCPXO over GKE multi-networking

For `a3-highgpu-8g` (TCPX) and `a3-megagpu-8g` (TCPXO) pools, provision the **classic
GKE GPU-bandwidth path**:

- **Dedicated data-plane VPCs/subnets** — TCPX needs **4** GPU-NIC networks, TCPXO
  needs **8** — each `mtu = 8896`, modelled as additional VPCs consumed by the node
  pool's `additional_node_network_configs`.
- **GKE multi-networking** objects: `GKENetworkParamSet` + `Network` per data-plane
  VPC, so pods get the extra `eth1..ethN` interfaces.
- The **TCPX/TCPXO NCCL plugin** DaemonSet + the `nccl-tcpx`/`nccl-tcpxo` env wiring on
  the workload (the Google-published installer/values), so NCCL uses the GPUDirect
  transport.

This is deliberately the **legacy mechanism** (not DRANET) because **DRANET GA does not
cover A3 High/Mega** — its hardware floor is A3 Ultra. H100 fabric must therefore use
`GKENetworkParamSet` until/unless DRANET extends downward (recorded as a revisit
trigger).

### D3 — H200 / B200: GPUDirect RDMA (RoCE) via GKE managed DRANET

For `a3-ultragpu-8g` (H200) and `a4-highgpu-8g` (B200) pools, adopt **GKE managed
DRANET** for the RDMA fabric:

- Enable **GKE managed DRANET** on the cluster (requires GKE **`1.35.2-gke.1842000+`**;
  this also satisfies the DRA-for-GPU floor from ADR-0036, `1.32.1-gke.1489001+`).
- Provision a **dedicated RoCE VPC** using the **RDMA network profile**
  (`google_compute_network` with the RoCE `network_profile`), `mtu = 8896`, attached to
  the pools as the CX-7 RDMA network.
- Define a **`netdev` `DeviceClass` + `ResourceClaimTemplate`** for the RDMA NICs (the
  DRANET driver), and have serving/training pods reference it **alongside** the
  GPU-compute `ResourceClaim` from ADR-0036. This keeps **one DRA mental model** across
  compute and network and lets **Volcano** (which already runs the DRA plugin) schedule
  GPU + NIC as one unit.

DRANET is chosen over hand-rolled `GKENetworkParamSet` for these families because it is
the **GA, Google-managed** path for A3 Ultra/A4 RoCE, it **reuses the DRA primitive the
estate already operates**, and it avoids a second, divergent multi-networking model for
the newest hardware. (H100 cannot use it yet — see D2.)

### D4 — GKE Inference Gateway for model-aware, cache-aware serving

Replace the vLLM **`ClusterIP`** front with the **GKE Inference Gateway** (Gateway API
inference extension):

- A new `gke-inference-gateway` module wiring a **`Gateway`** (GKE inference
  `GatewayClass`) → **`InferencePool`** (the set of vLLM replicas) → **`InferenceModel`**
  (per-model routing + criticality), with the **Body-Based Router** Service Extension
  that reads the model name from the OpenAI-style request body into
  `X-Gateway-Model-Name` for header-based routing.
- The gateway's endpoint-picker routes on **KV-cache utilisation, queue depth, and
  per-replica load / GPU metrics** (prefix/KV-cache-aware) instead of round-robin —
  the core throughput/latency win from the "Networking for AI inference" architecture.
- vLLM (`gpu-inference-vllm`) changes from `Service{type=ClusterIP}` to an
  `InferencePool` member; its existing VictoriaMetrics scrape and DRA GPU claim are
  unchanged. Multi-LoRA (already supported) maps onto multiple `InferenceModel` objects.

### D5 — Cloud Armor (and optional Model Armor) on the inference frontend

Front the Inference Gateway's load balancer with **Cloud Armor**
(`google_compute_security_policy`): WAF rules, **per-client rate limiting**, and
adaptive **DDoS** protection — the inference endpoint has **none** today. Wire
**Model Armor** as an additional Service Extension callout for prompt/response safety
**only if** a safety-screening requirement is confirmed (kept optional to avoid latency
on the hot path without a driving requirement). Heavyweight **Apigee** API management is
explicitly **out of scope** here (revisit trigger).

### D6 — Reaffirm scope guards (locked)

- **GKE Standard only** — unchanged from ADR-0036 (D6). The fabric DaemonSets (TCPX/TCPXO
  NCCL plugins) and DRANET driver and GPU Operator all require node-level access that
  Autopilot blocks. (The DRANET codelab runs on Autopilot, but the rest of this estate's
  GPU stack — Operator/DCGM/Volcano/Kata-CC — does not, so Standard stays.)
- **No TPU.** The reference codelab serves Gemma on **TPU v6e**; this estate is a
  committed **NVIDIA** stack (Operator/DCGM/DRA-compute are NVIDIA-bound). TPU is a
  parallel, non-reused universe — out of scope (revisit trigger).
- **Disaggregated prefill/decode is deferred** to a follow-up ADR (it depends on D3 +
  D4 landing first; see revisit trigger).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
  mandatory** on every VPC, network, security policy, Gateway, and DRA object here.

A reviewer checks conformance by confirming: (a) every GPU VPC sets `mtu = 8896` and
every GPU pool enables gVNIC (D1); (b) A3 High/Mega pools carry the data-plane networks
+ `GKENetworkParamSet` + NCCL plugin (D2); (c) A3 Ultra/A4 pools run on GKE
`1.35.2-gke.1842000+` with managed DRANET + a RoCE VPC + a `netdev` `ResourceClaimTemplate`
(D3); (d) vLLM is served via `InferencePool`/`InferenceModel` behind an Inference
Gateway, not `ClusterIP` (D4); (e) a Cloud Armor policy is bound to the inference LB
(D5); (f) every new resource carries the five ADR-0028 labels.

## Alternatives considered

### A1 — Keep default MTU / standard NICs (do nothing on the fabric)
*Rejected because:* it leaves all of GCP's GPU-network acceleration disabled and caps
multi-GPU/multi-host serving at VirtIO/1460-MTU throughput — the dominant cost for large
LLMs. D1 is one VPC argument + one node-pool flag; the cost/risk of inaction is far
higher than the change.

### A2 — One uniform fabric setting for all families
Pick a single networking mode (e.g. DRANET everywhere, or TCPX everywhere).
*Rejected because:* it is **technically impossible** — DRANET GA does not support A3
High/Mega or A100; GPUDirect-TCPX does not exist on `a2` (A100); RoCE is A3 Ultra/A4
only. A per-family matrix (D1–D3) is forced by the hardware, not a preference.

### A3 — `GKENetworkParamSet` (legacy multi-networking) for H200/B200 too
Use the classic multi-networking path uniformly, skip DRANET.
*Rejected because:* for A3 Ultra/A4, **GKE managed DRANET is the GA, Google-managed
path** and **reuses the DRA primitive the estate already runs** (ADR-0036). Hand-rolling
`GKENetworkParamSet` for RoCE on the newest hardware would mean operating two divergent
network models and forgoing managed lifecycle. (For H100, the reverse is true — DRANET
isn't available — hence D2 keeps the legacy path *only* where it must.)

### A4 — Keep the `ClusterIP` front + a plain HTTP(S) LB
Add a generic L7 LB but no inference-specific routing.
*Rejected because:* a generic LB is **model-blind and cache-blind** — it cannot route on
KV-cache locality, queue depth, or model identity, which is the entire point of the
"Networking for AI inference" architecture. The Inference Gateway endpoint-picker is the
mechanism that turns GPU metrics into routing decisions.

### A5 — Service-mesh (Istio/Envoy) model routing instead of Inference Gateway
Implement model-aware routing in a mesh.
*Rejected as the primary path because:* the **GKE Inference Gateway** is purpose-built
for LLM serving (InferencePool/InferenceModel + KV-cache-aware endpoint picking + Body-
Based Router) and is the Google-supported pattern; a mesh would re-implement this with
more moving parts. A mesh remains viable for east-west policy but is not the serving
front.

### A6 — Apigee + Model Armor as a mandatory gateway layer now
Put full API management (Apigee) and safety screening (Model Armor) on the hot path.
*Rejected as mandatory:* Apigee adds latency, cost, and operational surface without a
confirmed quota/monetisation requirement; Cloud Armor (D5) covers WAF/DDoS/rate-limit,
which is the actual gap. Model Armor is kept as an **optional** Service Extension behind
a confirmed safety requirement. Both are revisit triggers, not day-one scope.

### A7 — Adopt TPU serving (per the reference codelab)
Run Gemma-style serving on TPU v6e with DRANET.
*Rejected because:* the estate is a committed NVIDIA stack (Operator/DCGM/DRA-compute);
TPU shares none of it. The codelab informs the **DRANET** decision (D3), but its TPU
substrate is out of scope.

## Consequences

### Positive
- **Fabric matched to hardware:** each family runs its best available GPU-network path
  (gVNIC/jumbo for A100; TCPX/TCPXO for H100; RoCE/DRANET for H200/B200) instead of
  VirtIO/1460 across the board — the multi-GPU/multi-host throughput unlock.
- **One DRA model end-to-end:** H200/B200 fabric is a DRA `netdev` claim that composes
  with the GPU-compute claim ADR-0036 already schedules via Volcano — no second
  networking paradigm for the newest hardware.
- **Model-/cache-aware serving:** the Inference Gateway routes on KV-cache and load, not
  round-robin, improving TTFT/throughput and enabling clean multi-model (multi-LoRA →
  multi-`InferenceModel`) routing.
- **Perimeter for inference:** Cloud Armor brings WAF/DDoS/rate-limiting to an endpoint
  that has none today.
- **D1 is near-free and fleet-wide:** jumbo frames + gVNIC benefit every family at
  trivial change cost.

### Negative
- **Per-family node-pool/network complexity:** the node-pool module must express three
  fabric shapes (single-NIC; TCPX/TCPXO multi-VPC; RoCE DRANET) — more conditional
  surface than today's uniform pools.
- **Extra VPCs to manage:** TCPX needs 4 and TCPXO needs 8 data-plane VPCs; RoCE needs a
  dedicated RDMA VPC — multiplied per region (interacts with ADR-0036 D5 multi-region).
- **GKE version floor rises** to `1.35.2-gke.1842000+` for DRANET GA on the H200/B200
  pools (above the `1.32.1-gke.1489001+` DRA-compute floor) — a coordinated upgrade.
- **Serving migration is a behavioural change:** moving vLLM from `ClusterIP` to
  `InferencePool` alters the request path and must be validated against existing clients.

### Risks
- **R1 — multi-region GPU cost (highest, inherited).** Higher-bandwidth families
  (A3 Ultra/A4) and extra data-plane VPCs raise cost. *Mitigations:* per-family pools so
  expensive RoCE is used only where needed; A100/gVNIC remains the cheap default;
  scale-to-zero + spot (ADR-0036) unchanged; `gcp-billing-budget` 80/100/120% paging
  unchanged; ADR-0028 labels attribute fabric cost per `system`.
- **R4 — per-region GPU quota/capacity (inherited).** A3 Ultra/A4 availability is
  region- and quota-constrained and thinner than A100/H100. *Mitigation:* treat per-
  family, per-region GPU **and** the DRANET GKE version as explicit prerequisites before
  enabling a family in a region; prefer A100/H100 where A3-Ultra/A4 is unavailable.
- **Fabric/driver version skew.** TCPX/TCPXO NCCL plugin ↔ GKE ↔ NCCL ↔ GPU Operator,
  and DRANET ↔ GKE ↔ DRA driver ↔ Volcano, must be co-validated per region.
  *Mitigation:* pin all chart/plugin versions; validate against the region's GKE version
  in CI plan before apply (same discipline as ADR-0036).
- **Inference Gateway maturity.** The Gateway API inference extension is young; behaviour
  (endpoint-picker, Body-Based Router) must be validated under load before cutting prod
  traffic off `ClusterIP`. *Mitigation:* stage behind a canary InferencePool; keep the
  `ClusterIP` path revertible until the gateway is proven.
- **RoCE VPC/network-profile correctness.** A misconfigured RDMA network profile or MTU
  silently degrades to TCP or fails NCCL. *Mitigation:* an NCCL all-reduce bandwidth test
  (per the DRANET codelab) is an acceptance gate for D3 pools.

## Implementation notes

This ADR is **planning-only**: the PR that introduces it creates **no** GCP resources,
**no** new modules, and changes **no** node pool, VPC, or Service. Implementation is
**apply-gated** and lands as separate, plan/validate-only PRs.

**Conventions to match (verified against the repo):** `google ~> 6.0`, Terraform
`~> 1.11` (per `gcp-gke-gpu-nodepools/versions.tf`); every module takes a `labels`
(map(string)) input carrying the five ADR-0028 keys and merges it the way
`gcp-gke-gpu-nodepools` already does; Helm-release/namespace/toleration conventions
mirror the existing `gke-gpu-operator` / `gke-gpu-dcgm` / `gke-gpu-scheduling` modules.

### Module interface contracts (for the parallel module build)

**`gcp-gpu-vpc` (extend)** — jumbo frames + optional data-plane / RoCE networks.
- New inputs: `mtu` (number, default `8896`); `data_plane_network_count` (number,
  default `0` — `4` for TCPX, `8` for TCPXO pools); `enable_rdma_network` (bool, default
  `false` — provisions a RoCE `google_compute_network` with the RDMA `network_profile`
  for A3 Ultra/A4); all created networks/subnets carry the ADR-0028 `labels` and
  `mtu = 8896`.
- Outputs: `network_id`, `subnet_id`, `data_plane_network_ids` (list),
  `rdma_network_id`.

**`gcp-gke-gpu-nodepools` (extend, additive)** — gVNIC + per-family fabric attach.
- New inputs (per-pool, all optional, default off so existing pools are unchanged):
  `enable_gvnic` (bool, default `true` going forward), `fabric_mode`
  (`"none" | "tcpx" | "tcpxo" | "roce"`, default `"none"`),
  `additional_node_networks` (list — data-plane or RDMA networks/subnets to attach),
  `min_gke_version` guard for `roce` (`1.35.2-gke.1842000`).
- **Does not touch** spot/scale-to-zero/locality/Workload-Identity or the ADR-0036
  `operator_managed_driver` switch — fabric is layered on top.

**`gke-gpu-fabric` (new)** — H100/H100-Mega GPUDirect plumbing (D2).
- Installs the **TCPX/TCPXO NCCL plugin** DaemonSet + `GKENetworkParamSet` + `Network`
  objects for the data-plane VPCs. Inputs: `mode` (`tcpx`|`tcpxo`),
  `data_plane_networks` (list), `nccl_plugin_version`, `namespace`, `labels`.
- Outputs: `network_names` (list), `nccl_plugin_version`, `gke_network_param_set_names`.

**`gke-gpu-dranet` (new)** — H200/B200 RoCE via managed DRANET (D3).
- Enables GKE managed DRANET; ships the `netdev` **`DeviceClass`** + **`ResourceClaimTemplate`**
  for RDMA NICs. Inputs: `cluster_id`, `rdma_network_id` (from `gcp-gpu-vpc`),
  `device_class_name` (default `roce-netdev`), `claim_template_name` (default
  `rdma-all-nics`), `labels`. Composes with the ADR-0036 GPU-compute `ResourceClaimTemplate`
  (a pod references both claims).
- Outputs: `device_class_name`, `claim_template_name`, `dranet_enabled`.

**`gke-inference-gateway` (new)** — model-/cache-aware serving front (D4).
- Inputs: `gateway_class` (GKE inference class), `inference_pool_selector` (vLLM replica
  selector / port `8000`), `inference_models` (list: `{ name, criticality, target_model }`
  → `InferenceModel` objects, incl. LoRA adapters), `enable_body_based_router` (bool,
  default `true`), `cloud_armor_policy_id` (from `gcp-cloud-armor`, D5), `labels`.
- Outputs: `gateway_name`, `inference_pool_name`, `gateway_address`.
- **vLLM coupling (D4):** `gpu-inference-vllm` flips from `Service{type=ClusterIP}` to an
  `InferencePool` member (label selector unchanged); VictoriaMetrics scrape + DRA GPU
  claim unchanged. Keep the `ClusterIP` Service behind a feature flag until the gateway
  is canary-proven (revertible).

**`gcp-cloud-armor` (new)** — WAF/DDoS/rate-limit on the inference LB (D5).
- Inputs: `security_policy_name`, `rate_limit_threshold` (req/min/client),
  `waf_preconfigured_rules` (list), `enable_adaptive_protection` (bool, default `true`),
  `labels`. Attaches to the Inference Gateway backend service.
- Outputs: `security_policy_id`, `security_policy_name`.

**Multi-region wiring (interacts with ADR-0036 D5):** the per-family fabric VPCs
(`data_plane_network_count`, `enable_rdma_network`) and `gke-gpu-fabric` /
`gke-gpu-dranet` / `gke-inference-gateway` units are added to the **per-region GCP
`platform` Terragrunt stack**, gated on per-region accelerator availability. Cloud Armor
is a global/regional policy per the LB scope. Pin every chart/plugin ref (`?ref=vX.Y.Z`,
no `main`).

- Effort: **L** (two VPC/node-pool extensions + three new modules + a serving cutover +
  per-region/per-family wiring + a GKE version bump for the RoCE pools).
- Rollback: each module is independently revertible; the serving cutover keeps the
  `ClusterIP` path until the gateway is proven; the existing GPU plane (ADR-0036) and the
  EKS estate remain authoritative throughout.

## Revisit trigger

Re-open this decision if any of the following hold:
- **DRANET GA extends down to A3 High/Mega** — collapse D2's `GKENetworkParamSet` path
  into the unified DRANET model (D3) and retire `gke-gpu-fabric`.
- **A confirmed safety / quota / monetisation requirement appears** — promote Model
  Armor (D5) to mandatory and/or add Apigee (A6).
- **Disaggregated prefill/decode is prioritised** — open a follow-up ADR building on the
  D3 RoCE fabric + D4 Inference Gateway (separate prefill/decode pools + KV-cache
  transfer).
- **TPU enters scope** (a non-NVIDIA serving mandate) — revisit D6/A7 and the
  Operator/DCGM/DRA-compute assumptions.
- **The Inference Gateway extension proves insufficient under load** — revisit D4/A5
  (mesh-based routing) before widening prod traffic.
- **R1 cost envelope is breached** by RoCE/data-plane-VPC spend — narrow the families
  enabled per region or restrict A3-Ultra/A4 to training-only.

## References

- Google "Networking for AI inference" (GKE Inference Gateway, Body-Based Router,
  model-aware routing, Cloud Armor, multi-backend front):
  <https://docs.cloud.google.com/architecture/networking-for-ai-inference>
- GKE + DRANET high-performance-fabric codelab (DRA for `netdev`, multi-NIC pods, jumbo
  frames, vLLM serving):
  <https://codelabs.developers.google.com/codelabs/gke-autopilot-tpus-dranet-gemma>
- Accelerator-optimized machine families (A2/A3/A3-Mega/A3-Ultra/A4; GPUDirect-TCPX/
  TCPXO/RDMA per family): <https://docs.cloud.google.com/compute/docs/accelerator-optimized-machines>
- Maximize GPU network bandwidth — GKE Standard (GPUDirect-TCPX/TCPXO, multi-networking,
  MTU): <https://cloud.google.com/kubernetes-engine/docs/how-to/gpu-bandwidth-gpudirect-tcpx>
- GKE managed DRANET (GA `1.35.2-gke.1842000+`; A3 Ultra/A4/A4X, TPU v6e/v7x; RDMA
  ResourceClaimTemplate): <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/allocate-network-resources-dra>
- DRANET open source (kubernetes-sigs): <https://github.com/kubernetes-sigs/dranet>;
  Google OSS blog: <https://opensource.googleblog.com/2025/07/unlocking-high-performance-aiml-in-kubernetes-with-dranet-and-rdma.html>
- GKE managed DRANET + Inference Gateway (Google Cloud blog):
  <https://cloud.google.com/blog/topics/developers-practitioners/experimenting-with-gpus-gke-managed-dranet-and-inference-gateway-ai-deployment>
- GKE Inference Gateway (Gateway API inference extension; InferencePool/InferenceModel):
  <https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway>
- Cloud Armor (`google_compute_security_policy`):
  <https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_security_policy>
- In-repo: `terraform/modules/gcp-gpu-vpc`, `terraform/modules/gcp-gke-gpu-nodepools`,
  `terraform/modules/gpu-inference-dra`, `terraform/modules/gpu-inference-vllm`,
  `terraform/modules/gke-gpu-operator`, `terraform/modules/gke-gpu-dcgm`,
  `terraform/modules/gke-gpu-scheduling`, `failover-controller/`.
- Related ADRs: [ADR-0036](0036-gke-ml-infra-parity-multiregion.md) (GKE GPU
  compute parity + multi-region — this ADR extends it on the network/serving axis);
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (tagging/labeling —
  mandatory here).

---
*Doc-verified 2026-06-13 against official Google Cloud GKE / Compute Engine
accelerator-machine, GPUDirect-TCPX/TCPXO, GKE managed DRANET (GA), GKE Inference
Gateway, and HashiCorp `google_compute_security_policy` documentation. Planning-only
ADR — proposed, not yet implemented in platform-design. Extends WS-A on the networking
+ serving axis; implementation apply-gated.*
</content>
