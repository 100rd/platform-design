# ADR-0053: Bare-metal high-performance GPU fabric (RoCEv2/InfiniBand + SR-IOV/DRA) & on-prem serving front

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no `baremetal-gpu-fabric`, no
  `baremetal-inference-gateway` app, and no `baremetal-ingress-waf` module exist;
  GPU pods have **no RDMA NICs, no GPUDirect, no jumbo-frame data plane**, no
  model-/cache-aware serving front, and no WAF. The cloud analogue
  ([ADR-0042](0042-gpu-inference-networking-serving-uplift.md)) wired GPUDirect-TCPX/
  TCPXO + DRANET + GKE Inference Gateway + Cloud Armor — none of which exist on bare
  metal. `06-uk-datacenters.md` specifies 400 Gbps InfiniBand + NVSwitch + DRA but
  it is unimplemented.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: extends WS-A on the **networking/fabric + serving** axis that
  [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) scoped to compute;
  risk-register R4 (fabric misconfig → NCCL collapse). Bare-metal mirror of
  [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the GCP per-family
  fabric + Inference Gateway + Cloud Armor uplift).
- Supersedes: (none)
- Superseded by: (none)

## Context

[ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) brought the Talos
GPU plane to **compute parity** (driver via system extension, GPU Operator
driver-less, DCGM, DRA-compute, Volcano). Like ADR-0036 on GCP, it **deliberately
left the data path alone**: GPU↔GPU fabric, multi-NIC/RDMA pods, GPUDirect, and the
inference **serving front**. This ADR closes those — it is the **bare-metal mirror
of [ADR-0042](0042-gpu-inference-networking-serving-uplift.md)**.

Two forces, exactly parallel to ADR-0042:

1. **The fabric is the bottleneck for large models.** Tensor-/pipeline-parallel
   serving and distributed training are dominated by **NCCL** collective traffic.
   `06-uk-datacenters.md` already specifies the answer in fiction — **400 Gbps
   InfiniBand to pod + NVSwitch** on the H100 training and H200 inference nodes —
   and `ai-sre/knowledge/nccl-troubleshooting.md` already documents the failure
   modes (NCCL timeout on NVLink/fabric issues, AllReduce below theoretical max,
   "ensure NVSwitch is active", H100 NVLink ~450 GB/s baseline). The fabric exists
   *as a hardware requirement*; this ADR makes it a **Kubernetes-schedulable
   resource**.

2. **The serving front is naïve.** There is no model-aware router and **no WAF** in
   front of inference. ADR-0042's answer on GCP was the **GKE Inference Gateway** +
   **Cloud Armor**; on bare metal there is **no cloud LB and no Cloud Armor**, so
   the serving front must be built from **Gateway API on Cilium/Envoy Gateway** +
   an **on-prem WAF/rate-limit**, sitting on top of the
   [ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md) VIP/BGP layer.

The crucial bare-metal divergence from ADR-0042: GCP's fabric is a **per-machine-
family matrix** of *Google-managed* mechanisms (TCPX/TCPXO via `GKENetworkParamSet`;
RoCE via *managed* DRANET). On owned hardware we choose the **fabric technology
ourselves** — **RoCEv2** (Ethernet, ToR-friendly, the DRANET analogue) or
**InfiniBand** (dedicated fabric + subnet manager, what the UK doc specifies) — and
we **operate the RDMA plumbing ourselves** via either an **SR-IOV / RDMA-shared
device plugin** or **Cilium `netdev` DRA** (the open mirror of GCP's DRANET, since
DRANET upstream is `kubernetes-sigs/dranet` and works off-GKE too). The
"one DRA model for compute + network" principle from ADR-0042 D3 carries over: an
RDMA NIC becomes a `ResourceClaim` that composes with the GPU-compute claim Volcano
already schedules.

[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels are
mandatory on every fabric/serving resource, exactly as in ADR-0042.

## Decision

Add a **high-performance GPU fabric** and a **model-aware on-prem serving front**
to the Talos GPU plane, in six plan/validate-only sub-decisions. Nothing applies
without the gate; nothing is applied to hardware. This ADR **extends, and does not
re-open,** [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
(compute/operator/DRA-compute/Volcano/DCGM).

### D1 — Jumbo frames (MTU 9000) as the universal fabric baseline

Set **MTU 9000** on the GPU data-plane links — already specified by the `nic-tuning`
Ansible role (`06-uk-datacenters.md`) and aligned with the
[ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md) MTU-consistency requirement.
This is the floor for all GPU nodes (the bare-metal analogue of ADR-0042 D1's
jumbo-frames-everywhere), cutting packet count on bulk NCCL/tensor transfers, and a
prerequisite for D2/D3. For a **TCP-only day-0** bring-up (D5), MTU 9000 + standard
NICs is the *entire* fabric story until RDMA is validated.

### D2 — InfiniBand as the steady-state target fabric (RoCEv2 as the Ethernet alternative)

For the **H100 training** and **H200 inference** pools, the steady-state fabric is
**InfiniBand (400 Gbps, NVSwitch/NVLink intra-node)** — what `06-uk-datacenters.md`
specifies and what NCCL/NVSwitch assume. The data plane is provisioned by the
`network-fabric` + `gpu-nodes` Ansible roles (IB subnet manager, topology
verification — the doc's "NVSwitch, NVLink mesh, IB connectivity" pre-flight). The
**RoCEv2** alternative (RDMA over Converged Ethernet, ToR-switch-based, no separate
IB fabric/subnet-manager) is the **Ethernet path** where IB isn't available —
chosen per-DC by hardware, exactly as ADR-0042 forced a per-family matrix. Both
present the same thing to Kubernetes: **RDMA NICs to be claimed by pods** (D3).

### D3 — RDMA NICs to pods: SR-IOV device plugin (day-0 primary) → Cilium `netdev` DRA/DRANET (target, gated)

Expose the RDMA NICs to GPU pods as a **schedulable resource**, via the new
**`baremetal-gpu-fabric`** module, by one of two mechanisms:

- **Cilium `netdev` DRA / DRANET (`kubernetes-sigs/dranet`) — target end-state, behind the maturity gate below.** A `netdev`
  **`DeviceClass`** + **`ResourceClaimTemplate`** binds RDMA NICs to a pod, the
  **direct open mirror of GCP managed DRANET** (ADR-0042 D3). This keeps **one DRA
  mental model** across compute and network — a pod references the **GPU-compute
  `ResourceClaim` (ADR-0049) and the `netdev` claim together**, and **Volcano**
  (already running the DRA plugin) schedules GPU + NIC as one unit.
- **SR-IOV Network Device Plugin + Multus — alternative.** The mature, widely-run
  path: SR-IOV VFs surfaced as `rdma/...` extended resources, multi-NIC pods via
  Multus + an RDMA CNI. (On Talos the SR-IOV VF config + RDMA kernel modules are
  set by the `talos-machineconfig` kernel-module/sysctl surface + the
  `bare-metal-firmware` Ansible role's `SR-IOV enablement`.)

**DRANET maturity gate (the concrete adopt-DRANET-vs-SR-IOV-first condition).**
Default the **day-0 fabric to SR-IOV device plugin + Multus** (proven, stable on
bare metal today) and **adopt DRANET/DRA-`netdev` as the primary only when ALL of**:
(1) **DRA `netdev`/`ResourceClaim` is enabled and non-feature-gated** on our pinned
Talos/Kubernetes version (i.e. the DRA APIs are GA / on by default, not an alpha
feature gate we'd have to force); (2) the `kubernetes-sigs/dranet` driver has a
**tagged release validated against our exact NIC + kernel + Talos image** (it binds
RDMA `netdev`s, survives a node reboot, and exposes the right ResourceSlices); and
(3) an **NCCL all-reduce bandwidth test over a DRANET-claimed NIC matches the SR-IOV
baseline** (the D6 gate, run head-to-head). Until all three hold, SR-IOV is primary
and DRANET is staged behind a feature flag on the standby DC. Once they hold, DRANET
becomes primary (one DRA model with GPU compute) and SR-IOV drops to fallback. This
is the bare-metal mirror of ADR-0042's DRANET-vs-`GKENetworkParamSet` split, with
the roles of "managed" and "hand-rolled" both landing on us; the difference is we
**earn** the DRANET adoption against an explicit, testable bar rather than assuming
it. (D3 header lists DRANET "primary" as the **target** end-state per this gate.)

### D4 — Serving front: Gateway API on Cilium/Envoy Gateway + InferencePool/InferenceObjective (no cloud LB)

Replace any plain `ClusterIP` vLLM front with a **model-/cache-aware serving front**
built on **Gateway API**, delivered as the `baremetal-inference-gateway` ArgoCD app
— the on-prem mirror of ADR-0042 D4's GKE Inference Gateway:

- A **`Gateway`** on the **Cilium Gateway** (ADR-0009 is the estate's Cilium
  Gateway API decision) **or** the **Envoy Gateway** (`apps/infra/envoy-gateway`,
  ADR-0025) → **`HTTPRoute`** → **`InferencePool`** (the vLLM replicas) →
  **`InferenceObjective`** (v1 GA renamed `InferenceModel`→`InferenceObjective`;
  `InferencePool`/`HTTPRoute` unchanged — `InferencePool` graduated to v1/stable,
  with optional `InferencePoolImport`), the AI/ML-owner resource that maps a public
  model name → backends in the pool with traffic-split weights + criticality, using
  the **Gateway API Inference Extension** (these are **upstream** CRDs, not GKE-only)
  with an endpoint-picker (EPP) that routes on **KV-cache utilisation, queue depth,
  and per-replica GPU load** instead of round-robin. The VIP is from
  [ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md) (Cilium LB-IPAM + BGP), not
  a cloud LB. Multi-LoRA maps to multiple `InferenceObjective` objects (matching the
  existing vLLM multi-LoRA design in `03-ml-inference.md`).

### D5 — On-prem WAF / rate-limit (the Cloud Armor replacement); TCP-only day-0 fallback

- **WAF/rate-limit** at the serving edge via the new **`baremetal-ingress-waf`**
  module — **Cilium L7 policy + rate-limit** *or* **Envoy Gateway ratelimit +
  a WAF filter** — the on-prem mirror of ADR-0042 D5's Cloud Armor (WAF + per-client
  rate limit). There is **no cloud DDoS service**; volumetric DDoS protection is an
  upstream/ToR/edge-network concern (out of cluster scope, noted). This is surfaced
  as an OPEN DECISION (which WAF) and defaulted to **Cilium/Envoy rate-limit + a WAF
  ruleset**, with heavyweight API management (Apigee-equivalent) explicitly out of
  scope (revisit trigger), exactly as ADR-0042 D5/A6.
- **TCP-only is the day-0 correctness fallback.** Before the RDMA fabric is
  validated, NCCL runs over **TCP + jumbo frames** (D1) — correct but slow. The
  fabric (D2/D3) is promoted only after the **NCCL all-reduce bandwidth gate**
  passes.

### D6 — Reaffirm scope guards (locked)

- **NCCL all-reduce bandwidth test is a hard acceptance gate** for any RDMA pool
  (per `nccl-troubleshooting.md`: measure with `nccl-tests`, compare to the
  ~450 GB/s H100 NVLink baseline / the IB line rate). A pool that silently
  degrades to TCP fails the gate (R4).
- **No TPU; NVIDIA-only** — the estate is committed NVIDIA (Operator/DCGM/DRA from
  ADR-0049), same guard as ADR-0042 D6.
- **GPU-compute + `netdev` claims compose** under Volcano (one DRA model).
- **[ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) labels** on
  every fabric network, `DeviceClass`, `ResourceClaimTemplate`, `Gateway`,
  `InferencePool`, and WAF policy.

A reviewer checks conformance by confirming: (a) GPU data-plane MTU = 9000;
(b) the steady-state fabric is IB (or RoCEv2 per DC) with the subnet-manager/topology
pre-flight; (c) RDMA NICs are claimable via a `netdev` DRA `ResourceClaimTemplate`
(or SR-IOV `rdma/...`), composing with the GPU-compute claim under Volcano;
(d) vLLM is served via `InferencePool`/`InferenceObjective` behind a Cilium/Envoy
Gateway, **not** `ClusterIP`, on an ADR-0051 VIP; (e) a WAF/rate-limit policy is
bound to the serving front; (f) the NCCL all-reduce gate passes; (g) every resource
carries the five ADR-0028 keys.

## Alternatives considered

### A1 — TCP-only fabric (do nothing on RDMA)
Run NCCL over TCP + jumbo frames and skip RDMA.
*Rejected as the steady state because:* it caps multi-GPU/multi-host throughput far
below the IB/NVSwitch line rate the workloads need (the dominant cost for large
LLMs), contradicting the `06-uk-datacenters.md` 400 Gbps premise. **Kept as the
day-0 correctness fallback** (D5) until the RDMA gate passes — the same "MTU first,
fabric second" staging as ADR-0042 D1→D3.

### A2 — One uniform fabric for every node
Pick a single fabric mode estate-wide.
*Rejected because:* like ADR-0042 A2, it can be hardware-impossible — IB requires IB
HCAs + a subnet manager, RoCE requires lossless-Ethernet ToR config; a DC has one or
the other. The IB-default / RoCE-alternative split (D2) is forced by hardware, not
preference.

### A3 — SR-IOV/Multus everywhere instead of DRA
Use the classic SR-IOV device plugin + Multus for all RDMA, skip DRA.
*Rejected as the primary because:* it forgoes the **one-DRA-model** alignment
(ADR-0049 already runs DRA for GPU compute; ADR-0042 chose DRANET precisely to keep
one model). SR-IOV/Multus is a second, divergent multi-networking paradigm. **Kept
as the proven fallback** (D3) if DRANET off-GKE is immature for our hardware — the
mirror of ADR-0042 keeping `GKENetworkParamSet` only where DRANET can't reach.

### A4 — Plain `ClusterIP` + a generic L4/L7 LB for serving
Keep the naïve front + a generic load balancer.
*Rejected because:* a generic LB is **model-blind and cache-blind** — it cannot
route on KV-cache locality, queue depth, or model identity, which is the entire
point (ADR-0042 A4). The Gateway API Inference Extension endpoint-picker is the
mechanism that turns GPU metrics into routing decisions.

### A5 — Service-mesh (Istio) model routing instead of the Inference Gateway
Implement model-aware routing in a mesh.
*Rejected as the primary path because:* the **Gateway API Inference Extension**
(`InferencePool`/`InferenceObjective` + cache-aware picking) is purpose-built for LLM
serving and is the upstream-supported pattern; a mesh re-implements it with more
moving parts (ADR-0042 A5). A mesh remains viable for east-west policy, not the
serving front.

### A6 — Heavyweight API management (Apigee-equivalent) + safety screening on the hot path now
Put full API management + prompt/response safety inline as day-one scope.
*Rejected as mandatory:* it adds latency/cost/surface without a confirmed
quota/monetisation/safety requirement; Cilium/Envoy WAF + rate-limit (D5) covers
the actual gap. Kept as a revisit trigger (mirror of ADR-0042 A6/Model-Armor).

## Consequences

### Positive
- **Fabric matched to the hardware fiction:** IB/NVSwitch (or RoCEv2) at line rate
  instead of TCP/VirtIO — the multi-GPU/multi-host throughput unlock the
  `06-uk-datacenters.md` hardware was bought for.
- **One DRA model end-to-end:** the RDMA NIC is a `netdev` claim composing with the
  GPU-compute claim under Volcano — no second networking paradigm (DRANET parity
  with ADR-0042, off-GKE).
- **Model-/cache-aware serving without a cloud LB:** the Gateway API Inference
  Extension routes on KV-cache/load on top of the Cilium BGP VIP — the ADR-0042 D4
  win, on-prem.
- **A perimeter for inference:** the on-prem WAF/rate-limit brings ADR-0042 D5's
  Cloud-Armor function to an endpoint that has none.
- **Runbook already exists:** `nccl-troubleshooting.md` is the load-bearing
  acceptance gate + day-2 guide.

### Negative
- **We operate the RDMA plumbing:** IB subnet manager / RoCE lossless-Ethernet
  config, SR-IOV VFs or DRANET, topology verification — all ours (the
  `network-fabric`/`gpu-nodes`/`bare-metal-firmware` Ansible roles), surface the
  managed cloud hid.
- **Per-DC fabric divergence:** IB vs RoCE per DC means two fabric shapes to
  validate (mirrors ADR-0042's per-family complexity).
- **DRANET off-GKE maturity risk (now gated, not assumed):** the open `dranet`
  driver is younger off-GKE, so D3 makes **SR-IOV the day-0 primary** and adopts
  DRANET only once the explicit maturity gate (DRA-`netdev` GA on our Talos/k8s +
  a release validated on our NIC/kernel/image + an NCCL-match) is met — SR-IOV is
  the standing hedge, not a contingency.
- **Serving cutover is behavioural:** moving vLLM from `ClusterIP` to
  `InferencePool` changes the request path and must be validated under load
  (ADR-0042's same caveat).

### Risks
- **R4 — fabric misconfig silently degrades NCCL to TCP / fails collectives
  (highest for this ADR).** A wrong MTU, a bad IB subnet-manager/RoCE PFC config, or
  a mis-bound RDMA claim tanks training throughput or hangs collectives (the NCCL
  timeout/slow-AllReduce modes in `nccl-troubleshooting.md`). *Mitigations:* the
  **NCCL all-reduce bandwidth test is a hard gate** (D6); jumbo-frame + topology
  pre-flight (`gpu-nodes` role); DCGM NVLink/`DCGM_FI_PROF_NVLINK_TX_BYTES`
  alerting; stage on standby DC first.
- **DRANET/SR-IOV ↔ kernel ↔ NIC firmware ↔ NCCL skew.** *Mitigation:* pin the
  Talos image (RDMA kernel modules), NIC firmware (`bare-metal-firmware` role), and
  plugin versions; co-validate per DC (same discipline as ADR-0049 R2).
- **Inference Extension maturity** under load. *Mitigation:* canary the
  `InferencePool`, keep `ClusterIP` revertible until proven (ADR-0042's mitigation).
- **No cloud DDoS** for volumetric attacks. *Mitigation:* upstream/ToR/edge-network
  scrubbing is an out-of-cluster requirement, noted for the network-eng workstream.

## Implementation notes

This ADR is **planning-only**: the PR introducing it creates **no** fabric, **no**
serving front, **no** WAF, and applies **nothing to hardware**. Implementation is
**apply-gated**.

**Conventions to match:** Terraform `~> 1.11`; the `DeviceClass`/`ResourceClaimTemplate`
shape mirrors ADR-0049's GPU-compute DRA + ADR-0042's `gke-gpu-dranet`; the Gateway
shape reuses `apps/infra/envoy-gateway` / the Cilium Gateway (ADR-0009/0025). Carry
the five ADR-0028 keys on every resource.

### Module interface contracts (for the parallel module build)
**`baremetal-gpu-fabric`** — RDMA fabric to pods (SR-IOV day-0 / DRANET target per the maturity gate).
- Inputs: `cluster_endpoint`/`kubeconfig` (from `talos-cluster`),
  `fabric_mode` (`"infiniband" | "roce" | "tcp"`, default `"tcp"` for day-0),
  `rdma_mechanism` (`"sriov" | "dranet"`, default `"sriov"` until the D3 maturity gate is met, then `"dranet"`),
  `device_class_name` (default `rdma-netdev`),
  `claim_template_name` (default `rdma-all-nics`), `mtu` (default `9000`),
  `nccl_test_image` (the acceptance-gate `nccl-tests` image), `labels` (ADR-0028).
- Outputs: `device_class_name`, `claim_template_name`, `fabric_mode`.
- **Composition:** a serving/training pod references **both** this `netdev` claim
  and the ADR-0049 GPU-compute claim; Volcano schedules them as one unit.

**`baremetal-inference-gateway`** (ArgoCD app) — model-/cache-aware serving front.
- Inputs: `gateway_class` (Cilium or Envoy Gateway), `inference_pool_selector`
  (vLLM replica selector / port `8000`), `inference_objectives` (list:
  `{ name, criticality, target_model }` incl. LoRA — v1 `InferenceObjective`), `lb_vip_pool` (from
  `baremetal-cilium-lb`), `waf_policy_ref` (from `baremetal-ingress-waf`), `labels`.
- Outputs: `gateway_name`, `inference_pool_name`, `gateway_vip`.

**`baremetal-ingress-waf`** — on-prem WAF/rate-limit (Cloud Armor replacement).
- Inputs: `gateway_ref`, `rate_limit_threshold` (req/min/client),
  `waf_ruleset` (list), `mode` (`"cilium" | "envoy"`, default `"cilium"`), `labels`.
- Outputs: `waf_policy_ref`, `mode`.

- Effort: **L** (IB/RoCE data plane + DRANET/SR-IOV + serving cutover + WAF +
  NCCL-gate + per-DC wiring) — the bare-metal counterpart of ADR-0042's L effort.
- Rollback: each module independently revertible; the serving cutover keeps
  `ClusterIP` until the gateway is canary-proven; the GPU plane (ADR-0049) and the
  cloud estates remain authoritative; nothing applied to hardware.

## Revisit trigger

Re-open this decision if any of the following hold:
- **The DRANET maturity gate (D3) is met** — DRA `netdev` GA/un-gated on our pinned
  Talos/k8s, a `kubernetes-sigs/dranet` tagged release validated on our NIC+kernel+
  Talos image, and an NCCL all-reduce match to the SR-IOV baseline — **promote
  DRANET to primary and retire the SR-IOV fallback** (D3/A3).
- **A confirmed safety / quota / monetisation requirement appears** — promote the
  WAF to a full API-management/safety layer (D5/A6).
- **Disaggregated prefill/decode is prioritised** — open a follow-up building on the
  D3 RDMA fabric + D4 serving front (separate prefill/decode pools + KV-cache
  transfer), mirroring ADR-0042's deferred disaggregation.
- **TPU enters scope** (a non-NVIDIA mandate) — revisit D6 and the ADR-0049
  NVIDIA-only assumptions.
- **R4 fabric instability persists** despite the NCCL gate — fall back to TCP-only
  for the affected pool and re-investigate the IB/RoCE config.

## References

- DRANET (`kubernetes-sigs/dranet`; DRA for `netdev`/RDMA, works off-GKE):
  <https://github.com/kubernetes-sigs/dranet>,
  <https://opensource.googleblog.com/2025/07/unlocking-high-performance-aiml-in-kubernetes-with-dranet-and-rdma.html>
- Kubernetes Dynamic Resource Allocation (DRA): <https://kubernetes.io/docs/concepts/scheduling-eviction/dynamic-resource-allocation/>
- SR-IOV Network Device Plugin + Multus + RDMA CNI:
  <https://github.com/k8snetworkplumbingwg/sriov-network-device-plugin>,
  <https://github.com/k8snetworkplumbingwg/rdma-cni>
- NVIDIA GPUDirect RDMA: <https://docs.nvidia.com/cuda/gpudirect-rdma/>;
  NCCL + InfiniBand/RoCE: <https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/>
- Gateway API Inference Extension (`InferencePool`/`InferenceObjective`, upstream; v1 GA renamed `InferenceModel`→`InferenceObjective`; see GA migration guide):
  <https://gateway-api-inference-extension.sigs.k8s.io/>
  ; GA migration guide: <https://gateway-api-inference-extension.sigs.k8s.io/guides/ga-migration/>
- Cilium Gateway API / Envoy Gateway: <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>,
  <https://gateway.envoyproxy.io/>
- In-repo (HONORED): `docs/transaction-analytics/06-uk-datacenters.md` (400 Gbps IB,
  NVSwitch, DRA, `network-fabric`/`gpu-nodes`/`bare-metal-firmware` roles),
  `ai-sre/knowledge/nccl-troubleshooting.md` (the NCCL all-reduce acceptance gate),
  `docs/transaction-analytics/03-ml-inference.md` (vLLM multi-LoRA).
- In-repo references (shape mirrored): `terraform/modules/gke-gpu-dranet`,
  `terraform/modules/gke-inference-gateway`, `terraform/modules/gcp-cloud-armor`,
  `terraform/modules/gpu-inference-dra`, `apps/infra/envoy-gateway`.
- Related ADRs: [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the
  cloud fabric/serving uplift this mirrors),
  [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md) (compute base — DRA
  model + Volcano), [ADR-0051](0051-baremetal-networking-cilium-lb-bgp.md) (the VIP/BGP
  layer the serving front sits on), [ADR-0009](0009-cilium-gateway-api-ingress.md) /
  [ADR-0025](0025-envoy-gateway-secondary-l7.md) (the Gateway classes reused),
  [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md) (mandatory).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Bare-metal mirror of ADR-0042 (per-family fabric + Inference
Gateway + Cloud Armor). Extends WS-A on the fabric/serving axis; implementation
apply-gated. Drafted 2026-06-15.*
