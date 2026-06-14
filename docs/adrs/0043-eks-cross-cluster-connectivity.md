# ADR-0043: Cross-cluster connectivity for EKS — app-to-app access from cluster A to cluster B

- Status: **Proposed** — options survey + decision; plan/validate-only, apply-gated.
- platform-design status: **pending** — the substrate (Transit Gateway, ADR-0005) and
  the chosen east-west mechanism (Cilium ClusterMesh, ADR-0019) are scaffolded but
  `enable_clustermesh = false`; no cross-cluster app path is live yet.
- Date: 2026-06-14
- Authors: platform-team (solution-architect), network, security
- Related issues: builds on epic #252 (ADR-0019 Cilium capabilities); networking
  estate ADR-0003 / 0005 / 0009 / 0013 / 0023.
- Supersedes: (none)
- Superseded by: (none)

## Context

We run **two EKS clusters** and need a service in **cluster A** to call a service in
**cluster B** (east-west, service-to-service). This ADR surveys **every viable way** to
connect them, scores them against our estate, and picks a default plus the cases where a
different mechanism wins.

**The two clusters today (code-grounded):**

| | Cluster A | Cluster B |
|---|---|---|
| Example unit | `dev-eu-west-1-platform` | `staging-eu-central-1-platform` |
| Account | dev (111111111111) | staging (222222222222) |
| Region | eu-west-1 | eu-central-1 |
| VPC CIDR | 10.0.0.0/16 | 10.13.0.0/16 |
| EKS version | 1.32 | 1.32 |
| Endpoint | public | private-only |
| ClusterMesh | `false` | `true` (id euw1=1, euc1=2) |

Evidence: `terragrunt/dev/eu-west-1/platform/.terragrunt-stack/eks/terragrunt.hcl`,
`terragrunt/staging/eu-central-1/platform/.terragrunt-stack/eks/terragrunt.hcl`,
`terragrunt/staging/eu-central-1/account.hcl`.

**Decision drivers (the facts that pick the mechanism):**

1. **Different account + region + VPC.** Anything cross-cluster crosses an account and a
   region boundary — rules out same-VPC shortcuts.
2. **Pod CIDRs do NOT overlap.** Cilium runs in **ENI/native** mode
   (`apps/infra/cilium/values.yaml`), so pods get **VPC-routable** IPs from the VPC
   subnets — there is no overlay PodCIDR to collide. Non-overlapping, routable pod IPs is
   the single biggest enabler: it makes **pod-to-pod** routing (ClusterMesh) possible.
   *If a future cluster pair has overlapping CIDRs, the routable-IP methods are off the
   table and only the proxied methods (PrivateLink, VPC Lattice, ingress) work.*
3. **Substrate already exists.** A hub-and-spoke **Transit Gateway** (ADR-0005) provides
   cross-VPC routing; cross-region needs **TGW peering** (`tgw-peering` module). This is
   the L3 substrate most pod-level methods ride on.
4. **Cilium is the CNI** (ADR-0003) with **WireGuard** transit encryption, **default-deny**
   `CiliumNetworkPolicy`, and **ClusterMesh already scaffolded and piloted** (ADR-0019).
5. **Security posture is identity-first.** ADR-0013 mandates defense-in-depth (TGW route
   tables + SG + NACL) and **no direct VPC peering between workload accounts**; ADR-0023
   adds IAM-identity-scoped access (VPC Lattice).

The question is not "is there a way" — there are many. It is "which one per flow," so the
bulk of this ADR is the **options survey** (below) and the **selection matrix**.

## Decision

Adopt a **layered model**: one L3 substrate + a **default east-west mechanism** + a small
set of **alternative mechanisms** selected per-flow by an explicit rule. Nothing here
applies without the apply gate; this ADR ratifies the *menu and the default*, not a
specific rollout.

### D1 — Substrate: peered Transit Gateway (reuse ADR-0005)
Cross-cluster L3 reachability rides the existing hub-and-spoke **Transit Gateway**, with
**TGW peering** between the two regions (`terraform/modules/tgw-peering`,
`tgw-route-tables`). Per ADR-0013, routing stays **deny-by-default** with explicit route
tables; **no direct VPC peering** between workload accounts. This substrate is shared by
D2 and by the NLB/Route53 method.

### D2 — Default east-west mechanism: Cilium ClusterMesh
For pod/service A→B traffic, the **default** is **Cilium ClusterMesh** (ADR-0019), because
it is already on our data plane and fits the non-overlapping-routable-CIDR estate:

- **Global Services** — a `Service` annotated `service.cilium.io/global: "true"` is load-
  balanced across both clusters; A resolves B's service by its normal name with cross-
  cluster endpoints, with **topology-aware** / **local-first** routing.
- **Identity-based policy across clusters** — `CiliumNetworkPolicy` selects remote
  endpoints by `io.cilium.k8s.policy.cluster: <name>` (see
  `network-policies/gpu-inference/04-clustermesh-cross-cluster.yaml`), so A→B stays
  default-deny + explicitly allowed, with **L7** (HTTP method/path) rules.
- **Encrypted** end-to-end by the existing **WireGuard** layer; no new encryption stack.
- **Wiring** (already scaffolded): clustermesh-apiserver behind an **internal NLB**,
  **shared CA**, **distinct cluster IDs**, SG rules for ports **2379 / 4240 / 4244 /
  51871** (`terraform/modules/clustermesh-sg-rules`, `clustermesh-connect`), all over the
  D1 TGW. Flip `enable_clustermesh = true` per the ADR-0019 pilot checklist.

ClusterMesh is the default **only while pod CIDRs are non-overlapping and routable** (true
today). It gives the lowest-latency, most Kubernetes-native A→B path (no extra proxy hop).

### D3 — Alternative mechanisms, selected per-flow
ClusterMesh is not always the right tool. Use the **selection matrix** (below). The
sanctioned alternatives, each justified in the survey:

- **AWS PrivateLink** (endpoint service) — when the flow must be **unidirectional**,
  **provider/consumer** (vendor-style), **overlap-safe**, or tightly **account-isolated**.
- **VPC Lattice service network** (extends ADR-0023) — when you want **IAM-identity**
  authZ on HTTP/gRPC/TCP, **overlapping-CIDR tolerance**, and managed cross-account/region
  service-to-service without running mesh control planes.
- **Internal NLB + Route53 private hosted zone over TGW** — the **simplest** single-
  service exposure when ClusterMesh is overkill and you just need "B's service reachable
  by DNS from A."
- **Private ingress / Gateway API** (ADR-0009) — for **L7 north-south-style** exposure of
  B to A (TLS, host/path routing) when A should treat B as an external API, not a mesh
  peer.

### D4 — Selection rule (which mechanism per flow)

| Driver | ClusterMesh (D2) | PrivateLink | VPC Lattice | NLB+Route53 | Private Ingress |
|---|---|---|---|---|---|
| Pod CIDRs **overlap** | ❌ no | ✅ yes | ✅ yes | ⚠️ via LB IP | ✅ yes |
| Cross-account | ✅ | ✅ (built for it) | ✅ | ✅ (over TGW) | ✅ |
| Cross-region | ✅ (peered TGW) | ✅ | ✅ | ✅ | ✅ |
| Bidirectional mesh | ✅ | ❌ (1-way) | ✅ | ⚠️ per-LB | ⚠️ per-route |
| Identity authZ | Cilium id + L7 | endpoint policy | **IAM** + L7 | SG/NACL only | mTLS/JWT at GW |
| Extra proxy hop / latency | **none** | NLB hop | Lattice hop | NLB hop | GW hop |
| Service discovery | **native DNS** | endpoint DNS | Lattice DNS | Route53 | DNS + route |
| Ops cost | mesh upkeep | per-service | service network | per-service | gateway upkeep |
| Repo fit | **already piloted** | modules TBD | ADR-0023 (not impl) | NLB+R53 exist | ADR-0009 exists |

**Rule of thumb:** routable non-overlapping pods + many bidirectional services → **D2
ClusterMesh**. One-way/vendor/overlap/strict-isolation → **PrivateLink**. Identity-scoped
managed service-to-service or overlap → **VPC Lattice**. One simple service → **NLB+Route53**.
External-style L7 API → **private ingress**.

### D5 — Scope guards (locked)
- **No direct VPC peering** between workload accounts (ADR-0013 stands).
- **Default-deny** cross-cluster: every A→B flow needs an explicit `CiliumNetworkPolicy`
  (or endpoint/auth policy for the proxied methods). No blanket allow.
- **Non-overlapping CIDRs** remain a hard prerequisite for D2; new cluster pairs that
  cannot guarantee it must use a proxied method.
- **Encryption in transit** required end-to-end (WireGuard for D2; TLS for proxied).

## Alternatives considered — the full options survey

This is the "any/all ways" enumeration. Methods are grouped into the **L3 substrate** and
the **A→B connectivity mechanism** that rides it.

### Substrate options (L3 reachability between the VPCs)

**S1 — Transit Gateway, peered cross-region (CHOSEN, D1).** Hub-and-spoke TGW (ADR-0005) +
inter-region TGW peering. Scales to N VPCs, central route-table segmentation, already in
the estate. *Chosen* as the substrate.

**S2 — VPC peering (cross-region).** Direct 1:1 VPC peering. Simple and cheap for two VPCs,
no transitive routing. *Rejected:* ADR-0013 forbids direct peering between workload
accounts (no central segmentation/inspection), and it doesn't scale past a couple of VPCs.

**S3 — AWS Cloud WAN.** Managed global backbone replacing/segmenting TGW with policy. *Not
now:* TGW already meets the need; Cloud WAN is a larger migration than this flow warrants.

### Mechanism options (the actual A→B service access)

**M1 — Cilium ClusterMesh (CHOSEN default, D2).** Global services + cross-cluster identity
policy on the existing eBPF data plane; no extra proxy hop; WireGuard-encrypted. Requires
non-overlapping routable pod CIDRs (true today) and L3 reachability (S1). *Chosen.*

**M2 — AWS PrivateLink / VPC endpoint service.** B publishes an **NLB-backed endpoint
service**; A consumes via an **interface VPC endpoint**. Strengths: built for **cross-
account**, **CIDR-overlap-proof** (A only ever sees the endpoint ENI in its own VPC),
**unidirectional** by design, fine-grained endpoint **allow-listing**. Weaknesses: one-way
(A→B only; reverse needs a second service), **per-service** plumbing, an NLB hop of
latency, TCP/TLS only (no L7 routing). *Sanctioned alternative* for provider/consumer,
overlapping-CIDR, or strict-isolation flows.

**M3 — VPC Lattice service network.** A managed **application-layer** network: B registers
its service, A is associated to the **service network**, traffic is authorized by **IAM
auth policies** (HTTP/gRPC/TCP), across account/region, **tolerant of overlapping CIDRs**.
ADR-0023 already adopts Lattice for *resource* access (RDS); this extends the same
primitive to **inter-cluster service-to-service**. Strengths: identity-first, managed, no
mesh control plane, overlap-safe. Weaknesses: a Lattice data-path hop, AWS-specific,
ADR-0023 not yet implemented. *Sanctioned alternative* for identity-scoped managed flows.

**M4 — Internal NLB + Route53 private hosted zone (over TGW).** B exposes its service on an
**internal NLB**; a **private hosted zone** (shared cross-VPC via association over S1)
resolves the name; A calls it directly. Strengths: dead simple, no new control plane, uses
modules we already have (`nlb-ingress`, route53). Weaknesses: SG/NACL-only authZ (no
workload identity), per-service LBs, an NLB hop, manual DNS lifecycle. *Sanctioned* for the
simplest single-service case.

**M5 — Private ingress / Gateway API (ADR-0009).** B fronts its service with a
**Cilium/Envoy Gateway** (or ALB) on a **private** address; A treats B as an external L7
API (TLS, host/path, optional mTLS/JWT at the gateway). Strengths: real **L7** controls,
familiar API-gateway model, good for team/tenant boundaries. Weaknesses: gateway to
operate, a proxy hop, north-south semantics (not transparent mesh). *Sanctioned* for
external-style API exposure.

**M6 — Dedicated service mesh, multi-cluster (Istio / Linkerd).** A second mesh spanning
both clusters (east-west gateways, shared trust). Strengths: rich L7, mTLS, traffic
shaping. *Rejected as default:* it **duplicates** what Cilium ClusterMesh already gives us
on the data plane we run — a second control plane and sidecar/!sidecar story for no net
new capability we need. Revisit only if a mesh-only feature becomes a hard requirement.

**M7 — OSS multi-cluster overlays (Submariner, Skupper).** Submariner builds an encrypted
inter-cluster tunnel + service discovery; Skupper builds an app-layer VAN. Strengths:
cloud-agnostic, can bridge overlapping CIDRs (Submariner global-net). *Rejected:* adds a
parallel tunneling/control stack alongside Cilium+TGW for capability we already have;
justified only in multi-cloud, which is out of scope here.

**M8 — AWS Global Accelerator.** Anycast edge IPs with health-checked failover to regional
endpoints (`global-accelerator` module, enabled in staging). *Not an east-west tool:* it is
**north-south** (user→service, multi-region failover). Noted so it isn't miscast as A→B
service connectivity; it complements, not replaces, M1–M5.

**M9 — Endpoint/Service mirroring or KubeFed-style federation.** Manually mirror B's
`EndpointSlice`/`Service` into A, or use Kubernetes federation. *Rejected:* brittle,
hand-rolled discovery that ClusterMesh automates and AWS-native options supersede.

**M10 — Status quo (no cross-cluster path).** Keep clusters isolated; integrate only via
shared external systems (queues, public APIs). *Rejected:* the requirement is direct A→B
service access; isolation doesn't meet it.

## Consequences

### Positive
- A clear **default** (ClusterMesh) that reuses the data plane and substrate we already
  pay for — lowest latency, native discovery, identity + L7 policy, WireGuard-encrypted.
- An explicit **per-flow selection rule** so overlapping-CIDR, one-way, vendor, or
  identity-scoped flows have a sanctioned home (PrivateLink / Lattice / NLB+R53 / ingress)
  instead of being forced through one mechanism.
- Builds directly on ADR-0005/0013/0019/0023 — no new architectural axioms.

### Negative
- More than one cross-cluster mechanism to document and operate (mitigated: ClusterMesh is
  the default; others are exceptions chosen by the matrix).
- ClusterMesh adds clustermesh-apiserver + cross-cluster SG surface to run.

### Risks
- **Overlapping CIDRs in a future pair** would silently break ClusterMesh routing.
  *Mitigation:* D5 prerequisite + IPAM review before enabling D2; fall back to a proxied
  method (M2/M3/M5).
- **Cross-region latency** on east-west calls. *Mitigation:* prefer local-first/topology-
  aware routing; co-locate chatty services; treat cross-region A→B as best-effort, not a
  hot synchronous path.
- **Blast radius / lateral movement** from a flat mesh. *Mitigation:* default-deny +
  per-flow `CiliumNetworkPolicy` (D5), TGW route-table segmentation (ADR-0013), Tetragon
  observe (ADR-0019).
- **clustermesh-apiserver exposure.** *Mitigation:* internal NLB only, shared CA, SG-scoped
  to peer VPC CIDRs (`clustermesh-sg-rules`), WireGuard.
- **PrivateLink/Lattice per-service sprawl** if overused. *Mitigation:* reserve for the
  matrix cases; default stays ClusterMesh.

## Implementation notes

Planning-only. Implementation is **apply-gated** and lands per-mechanism as separate
plan/validate PRs. Phasing:

1. **Substrate (D1):** enable TGW peering + routes between the two regions
   (`tgw-peering`, `tgw-route-tables`); validate VPC-to-VPC reachability. Keep deny-by-
   default route tables (ADR-0013).
2. **ClusterMesh pilot (D2):** follow the ADR-0019 checklist — `enable_clustermesh = true`,
   distinct cluster IDs (euw1=1, euc1=2), shared CA, `clustermesh-sg-rules` for 2379/4240/
   4244/51871, clustermesh-apiserver internal NLB. Prove one **global Service** A→B with a
   default-deny `CiliumNetworkPolicy` allowing exactly that flow + an L7 rule.
3. **Alternatives as needed:** add a `privatelink-endpoint-service` module and/or extend
   ADR-0023 VPC Lattice to a service network when a flow hits the matrix; NLB+Route53 is
   already available for the simple case.
4. **Conformance:** every cross-cluster flow has an explicit policy; CIDRs verified non-
   overlapping before any D2 enablement; transit encrypted.

Reuse existing modules: `transit-gateway`, `tgw-peering`, `tgw-route-tables`,
`clustermesh-connect`, `clustermesh-sg-rules`, `cilium`, `nlb-ingress`, `route53-resolver`,
`vpc-lattice-resource`. New modules only where the matrix demands (PrivateLink endpoint
service; Lattice service network).

- Effort: **M** for D1+D2 (mostly enabling scaffolded pieces); **per-flow S–M** for
  alternatives.
- Rollback: each mechanism is independently revertible; ClusterMesh reverts to
  `enable_clustermesh = false`; TGW routes are removable; no clusters are mutated by this
  ADR.

## Revisit trigger
- A cluster pair **cannot** guarantee non-overlapping routable pod CIDRs → demote D2 for
  that pair, default to PrivateLink/Lattice.
- A **mesh-only L7 feature** (advanced traffic shaping, per-request mTLS identity beyond
  Cilium) becomes a hard requirement → re-evaluate M6.
- **Multi-cloud** enters scope → re-evaluate M7 (Submariner/Skupper).
- Cross-region east-west becomes a **hot synchronous** dependency → reconsider data
  locality / active-active topology rather than stretching the mesh.

## References

- Cilium ClusterMesh: <https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/>
- Cilium Global Services: <https://docs.cilium.io/en/stable/network/clustermesh/services/>
- AWS PrivateLink: <https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html>
- AWS VPC Lattice: <https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html>
- AWS Transit Gateway peering: <https://docs.aws.amazon.com/vpc/latest/tgw/tgw-peering.html>
- EKS multi-cluster guidance: <https://aws.github.io/aws-eks-best-practices/networking/subnets/>
- Submariner: <https://submariner.io/> · Skupper: <https://skupper.io/>
- In-repo diagram: `docs/architecture/eks-cross-cluster-connectivity.excalidraw` (ClusterMesh design).
- In-repo: `terraform/modules/{transit-gateway,tgw-peering,tgw-route-tables,clustermesh-connect,clustermesh-sg-rules,cilium,nlb-ingress,route53-resolver,vpc-lattice-resource}`;
  `apps/infra/cilium/values.yaml`; `network-policies/gpu-inference/04-clustermesh-cross-cluster.yaml`;
  `terragrunt/staging/eu-central-1/account.hcl`.
- Related ADRs: [ADR-0003](0003-cilium-over-aws-vpc-cni.md) (Cilium CNI),
  [ADR-0005](0005-hub-spoke-transit-gateway.md) (Transit Gateway),
  [ADR-0009](0009-cilium-gateway-api-ingress.md) (Gateway API),
  [ADR-0013](0013-inter-vpc-access-security-model.md) (inter-VPC security),
  [ADR-0019](0019-harvest-cilium-ebpf-capabilities.md) (ClusterMesh pilot),
  [ADR-0023](0023-vpc-lattice-resource-connectivity.md) (VPC Lattice).

---
*Options-survey ADR — proposed, not yet implemented. Substrate = ADR-0005 TGW; default
east-west = ADR-0019 Cilium ClusterMesh; alternatives (PrivateLink / VPC Lattice /
NLB+Route53 / private ingress) selected per the D4 matrix. Implementation apply-gated.*
</content>
