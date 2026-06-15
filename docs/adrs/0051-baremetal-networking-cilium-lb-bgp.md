# ADR-0051: Bare-metal networking — Cilium CNI + LB-IPAM/BGP vs MetalLB

- Status: **Proposed** — plan/validate-only; implementation apply-gated.
- platform-design status: **pending** — no `baremetal-cilium-lb` module exists; the
  cluster has no CNI, no service-VIP advertisement, and no BGP peering to the ToR
  switches. The repo already ships a `cilium` module and a
  `ai-sre/knowledge/cilium-bgp-issues.md` runbook (which references `cilium bgp
  peers`, hold timers, ToR max-prefix), but nothing wires Cilium LB-IPAM/BGP on
  bare metal, and there is no cloud load-balancer to fall back on.
- Date: 2026-06-15
- Authors: platform-team (solution-architect)
- Related issues: WS-A "Bare-metal GPU cluster foundation & elasticity"
  (Bare-Metal ML Platform plan, `docs/baremetal-ml-platform/IMPLEMENTATION_PLAN.md`);
  risk-register R6 (BGP session flap). On bare metal there is **no cloud VPC + no
  cloud LB**, so this replaces both `gcp-gpu-vpc` and the cloud-LB layer of
  [ADR-0042](0042-gpu-inference-networking-serving-uplift.md).
- Supersedes: (none)
- Superseded by: (none)

## Context

In the cloud etalon, two things come for free that **do not exist on bare metal**:
a managed **VPC** (`gcp-gpu-vpc`) and a managed **load balancer** (the GKE
Inference Gateway's backing L7 LB + Cloud Armor,
[ADR-0042](0042-gpu-inference-networking-serving-uplift.md) D4/D5). On owned
hardware we must provide both ourselves: a **CNI** for pod networking and a
**bare-metal load-balancer** to expose service VIPs to the outside world over the
physical network — there is no cloud control plane to hand us an external IP.

The repo already leans toward **Cilium**: a `cilium` Terraform module exists, the
EKS estate runs Cilium (ADR-0003 "Cilium over aws-vpc-cni"), and crucially the
`ai-sre/knowledge/cilium-bgp-issues.md` runbook already documents **Cilium BGP**
operations (`cilium bgp peers`, hold/keepalive timers, ToR `max-prefix`, route
limits, session flap) — strongly implying **BGP is the intended bare-metal
path**. `docs/transaction-analytics/06-uk-datacenters.md` also names a
`network-fabric` Ansible role that configures "BGP peerings" on the ToR switches
and **MTU 9000** on the 100 GbE links (`nic-tuning`), which is the substrate this
ADR's control-plane configuration peers with.

The decision is **which bare-metal LB mechanism** advertises service VIPs:
**Cilium's own LB-IPAM + BGP control plane** (one networking stack), or a separate
**MetalLB** (a second, dedicated bare-metal LB component). This is the bare-metal
analogue of "how does a request reach a serving replica" from ADR-0042, but at the
L3/L4 VIP-advertisement layer rather than the L7 inference-routing layer (the L7
serving front — Gateway API + InferencePool — lands in WS-A's
`baremetal-inference-gateway` app and the WAF in
[ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md)).

## Decision

Use **Cilium as the CNI** in kube-proxy-less mode and **Cilium LB-IPAM + the
Cilium BGP control plane** as the bare-metal load-balancer, in five
plan/validate-only sub-decisions. Nothing applies without the gate; nothing is
applied to hardware.

### D1 — Cilium CNI, kube-proxy-less, eBPF datapath

The new **`baremetal-cilium-lb`** module installs **Cilium** as the cluster CNI in
**kube-proxy replacement** mode (eBPF datapath), reusing the existing `cilium`
module's shape and the estate's ADR-0003 decision. This is the single networking
stack for pod-to-pod, policy (CiliumNetworkPolicy — which ADR-0028 §"Cilium Network
Security Policies" already relies on for `platform.system` micro-segmentation),
and the LB/BGP control plane below. Talos is **kube-proxy-less-friendly** (its
machine config can disable kube-proxy), so this composes cleanly with
[ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md).

### D2 — Service VIPs via Cilium LB-IPAM (not a cloud LB, not NodePort)

Expose `Service{type=LoadBalancer}` via **Cilium LB-IPAM**: a
`CiliumLoadBalancerIPPool` carves VIPs from the DC's allocated service-VIP CIDR,
and Cilium assigns them — replacing the cloud's "ask the provider for an external
IP." This is the mechanism the GKE Inference Gateway's LB provided in ADR-0042; on
bare metal the VIP is **ours**, drawn from a pool, advertised by D3.

### D3 — VIP reachability via the Cilium BGP control plane (peering the ToR switches)

Advertise the LB-IPAM VIPs (and, optionally, pod CIDRs) to the **top-of-rack
switches via the Cilium BGP control plane** (`CiliumBGPClusterConfig` /
`CiliumBGPAdvertisement` / `CiliumBGPPeerConfig`), peering the BGP config the
`network-fabric` Ansible role sets on the ToR side (`06-uk-datacenters.md`). This
is the path the `cilium-bgp-issues.md` runbook already operates, so its guidance
is **load-bearing configuration**, not just troubleshooting:

- **Hold timer 180 s** (not the default 90 s) to tolerate keepalive delay under
  CPU pressure on busy GPU nodes (the runbook's "Hold Timer Too Aggressive" fix).
- **ToR `max-prefix` sized** for the cluster's advertised routes (the runbook's
  "Route Limit Exceeded" fix).
- **MTU consistency** end-to-end (the runbook's first check) — MTU 9000 from
  `nic-tuning`, consistent across the BGP path, so a flap isn't induced by MTU
  mismatch.

### D4 — MetalLB is the documented fallback, not the default

**MetalLB** (L2 or BGP mode) is recorded as the **fallback** if a Cilium
LB-IPAM/BGP limitation surfaces (e.g. a ToR that the Cilium BGP control plane
cannot peer, or a feature MetalLB has that Cilium lacks at our version). It is
**not** the default because adding MetalLB means operating **two networking
components** (Cilium + MetalLB) with overlapping responsibility, a second BGP
speaker to reason about, and no `platform.system`-aware policy integration. The
single-stack Cilium path keeps one eBPF datapath, one BGP speaker, one runbook.

### D5 — Reaffirm: ADR-0028 labels; CiliumNetworkPolicy uses `platform.system`

Every networking resource (pools, BGP configs, policies) carries the five ADR-0028
keys, and **CiliumNetworkPolicies key on `platform.system`** for micro-segmentation
exactly as ADR-0028 §"Cilium Network Security Policies" specifies — so the
bare-metal network policy model is identical to the cloud one. The
namespace-per-tenant `NetworkPolicy` default-deny from `06-uk-datacenters.md` is
honoured (the `tenant-bootstrap` chart's policies sit on top of this CNI).

A reviewer checks conformance by confirming: (a) Cilium is installed
kube-proxy-less; (b) a `CiliumLoadBalancerIPPool` exists for the service-VIP CIDR;
(c) the Cilium BGP control plane peers the ToR with hold-timer 180 s and a sized
max-prefix; (d) MetalLB is **absent** (fallback only); (e) policies key on
`platform.system`; (f) every resource carries the five ADR-0028 keys.

## Alternatives considered

### A1 — MetalLB as the primary bare-metal LB (Cilium CNI only for pod networking)
Use Cilium for the CNI but MetalLB for `LoadBalancer` services.
*Rejected as the default because:* it runs **two networking components** with
overlapping LB/BGP responsibility, a second BGP speaker, and no
`platform.system`-aware policy tie-in — more surface, more failure modes, two
runbooks. The repo already invested in **Cilium BGP** (the
`cilium-bgp-issues.md` runbook exists), so the single-stack Cilium path is the
lower-surface choice. **Kept as the documented fallback** (D4) for ToR/feature
edge cases.

### A2 — NodePort + an external hardware/virtual load-balancer
Expose services via NodePort and front them with an external LB appliance.
*Rejected because:* it pushes VIP management and health-checking outside the
cluster (a separate appliance to operate, no Cilium policy integration, manual
node-IP/health wiring), and it does not give clean `Service{type=LoadBalancer}`
semantics that the serving stack (Gateway API / InferencePool) expects.

### A3 — Cloud VPC + cloud LB (i.e. don't do bare-metal networking)
Run the workloads where a managed VPC/LB exists.
*Rejected because:* the whole premise (ADR-0049) is **owned bare metal**; there is
no cloud VPC/LB in the UK DCs. This is the "do nothing" option and it does not meet
the requirement.

### A4 — L2-only (ARP/NDP) VIP announcement, no BGP
Use Cilium LB-IPAM with L2 announcements instead of BGP.
*Rejected as the steady-state because:* L2 announcement is single-failure-domain
and does not scale across racks/ToRs the way BGP ECMP does; the DC fabric is
explicitly BGP-peered (`network-fabric` role) and the runbook is BGP-shaped. L2 is
acceptable only as a tiny-scale bootstrap, subsumed by the MetalLB-L2 fallback (D4).

## Consequences

### Positive
- **One networking stack:** Cilium provides CNI, kube-proxy replacement, LB-IPAM,
  BGP, **and** `platform.system` policy in a single eBPF datapath — one component,
  one runbook (`cilium-bgp-issues.md`), one mental model shared with the EKS
  estate.
- **VIPs we own:** service IPs are drawn from our pool and advertised over our
  fabric — no dependence on a cloud control plane.
- **Policy parity with the cloud:** CiliumNetworkPolicy on `platform.system` is
  identical to ADR-0028's cloud model; the namespace-per-tenant default-deny rides
  on top unchanged.
- **Runbook already exists:** the operational guidance (hold timer, max-prefix,
  MTU) is written and becomes load-bearing config, shortening time-to-stable.

### Negative
- **BGP is an operational surface** the managed cloud hid: peer state, route
  limits, and session flaps are now ours to monitor (R6) — WS-D adds the BGP
  session-state panel.
- **ToR coordination:** the Cilium BGP config must match the `network-fabric`
  Ansible-set ToR config (ASNs, timers, max-prefix); a mismatch flaps the session.
- **Single-stack risk:** betting on Cilium for LB+BGP means a Cilium LB/BGP bug
  affects VIP reachability cluster-wide; the MetalLB fallback (D4) is the hedge.

### Risks
- **R6 — Cilium BGP session flap (highest for this ADR).** Per
  `cilium-bgp-issues.md`: hold-timer too aggressive under CPU pressure, ToR
  route-limit exceeded, or an MTU mismatch flaps the peer and drops VIP
  reachability. *Mitigations:* hold-timer 180 s; ToR max-prefix sized; MTU 9000
  consistent end-to-end; **BGP `cilium_bgp_peer_status` alerting** in WS-D; MetalLB
  L2/BGP as the documented fallback.
- **Bootstrap ordering:** the CNI must be up before any workload schedules — WS-A's
  internal sequencing puts `baremetal-cilium-lb` immediately after `talos-cluster`
  and before storage/GPU (plan §5).

## Implementation notes

This ADR is **planning-only**: the PR introducing it creates **no** CNI install,
**no** BGP peering, and applies **nothing to hardware**. Implementation is
**apply-gated**.

**Conventions to match:** Terraform `~> 1.11`; reuse the `cilium` module's
Helm-release shape; carry the five ADR-0028 `platform_*` labels on every resource
and `platform.*` on the policies.

### Module interface contract (for the parallel module build)
**`baremetal-cilium-lb`** — Cilium CNI (kube-proxy-less) + LB-IPAM + BGP.
- Inputs: `cluster_endpoint`/`kubeconfig` (from `talos-cluster`),
  `chart_version` (Cilium), `kube_proxy_replacement = true`,
  `lb_ipam_pools` (list of `{ name, cidr }` for service VIPs),
  `bgp_peers` (list of `{ peer_address, peer_asn, local_asn, hold_time_seconds =
  180 }` — peers the ToR config from the `network-fabric` Ansible role),
  `advertise_pod_cidr` (bool, default false), `mtu` (default `9000`),
  `enable_metallb_fallback` (bool, default **false** — fallback only),
  `namespace` (default `kube-system`), `labels` (map(string), ADR-0028).
- Outputs: `cilium_version`, `lb_ipam_pool_names` (list), `bgp_peer_addresses`
  (list).

- Effort: **M** (one CNI/LB/BGP module + ToR-config coordination + the WS-D BGP
  panel).
- Rollback: revert the module; the cluster falls back to no external VIPs (serving
  unreachable) — so this is sequenced early and validated before serving lands;
  the cloud estate stays authoritative.

## Revisit trigger

Re-open this decision if any of the following hold:
- **A Cilium LB-IPAM/BGP limitation** blocks a required ToR peering or feature —
  promote **MetalLB** (D4/A1) for the affected scope.
- **The DC fabric moves off BGP** (e.g. an EVPN/VXLAN overlay the ToR manages) —
  re-evaluate D3 (the advertisement mechanism).
- **Cilium changes the BGP control-plane API** (the `CiliumBGP*` CRDs) in a way
  that breaks the `cilium-bgp-issues.md` runbook — re-validate the config surface.

## References

- Cilium LB-IPAM: <https://docs.cilium.io/en/stable/network/lb-ipam/>
- Cilium BGP control plane (`CiliumBGPClusterConfig`/`CiliumBGPAdvertisement`/
  `CiliumBGPPeerConfig`): <https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/>
- Cilium kube-proxy replacement:
  <https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/>
- Talos + Cilium (kube-proxy-less): <https://www.talos.dev/latest/kubernetes-guides/network/deploying-cilium/>
- MetalLB (fallback): <https://metallb.universe.tf/>
- In-repo (HONORED): `ai-sre/knowledge/cilium-bgp-issues.md` (load-bearing config +
  runbook), `docs/transaction-analytics/06-uk-datacenters.md` (`network-fabric` /
  `nic-tuning` roles, ToR BGP, MTU 9000).
- In-repo references (shape): `terraform/modules/cilium`,
  `terraform/modules/gpu-inference-cilium`.
- Related ADRs: [ADR-0049](0049-baremetal-gpu-k8s-talos-foundation-multidc.md)
  (foundation), [ADR-0003](0003-cilium-over-aws-vpc-cni.md) (Cilium as the estate
  CNI), [ADR-0042](0042-gpu-inference-networking-serving-uplift.md) (the cloud LB
  layer this replaces on bare metal),
  [ADR-0053](0053-baremetal-gpu-fabric-roce-infiniband.md) (the L7 serving front +
  WAF sits above this), [ADR-0028](0028-unified-platform-tagging-and-labeling-taxonomy.md)
  (CiliumNetworkPolicy on `platform.system`).

---
*Planning-only ADR — proposed, not implemented; nothing applied to hardware
(mock/emulation repo). Replaces the cloud VPC + cloud-LB layer on bare metal. WS-A;
implementation apply-gated. Drafted 2026-06-15.*
