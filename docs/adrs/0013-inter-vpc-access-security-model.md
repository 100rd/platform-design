# ADR-0013: Inter-VPC access security model (TGW segmentation + cross-estate VPN join)

- Status: **Accepted** — decision is *adopted (live in source estate)*; the
  legacy-side return routes and the prod NACL backstop are tracked as
  cross-account follow-ups (see *Consequences*), so those sub-parts are
  *design-target*. Builds on ADR-0005 (hub-spoke TGW).
- Date: 2026-06-03
- Authors: platform-team, security
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform is merging two network estates and adding a VPN that spans both, so
the inter-VPC security model must guarantee that production data-plane VPCs stay
isolated from dev/standard even with a cross-estate VPN in play. (Account IDs and
specific CIDRs from the source estate are intentionally omitted here; the
platform-design mock uses representative ranges.)

1. **Legacy estate** — internally a flat **VPC peering mesh** (admin / dev-EKS /
   prod / analytics-prod VPCs). The legacy VPN server runs in the admin VPC in
   NAT/masquerade mode, so its client pool is SNAT'd and not visible at the AWS
   routing layer. The legacy admin/prod/dev VPCs are **already attached** to the
   hub TGW, but the attachments are **inert** — there are zero custom TGW route
   tables, so no traffic flows through the TGW yet.

2. **New estate** (this repo) — **hub-and-spoke TGW** (ADR-0005) in the Network
   account, with planned spoke/shared/prod VPC ranges. `modules/tgw-routing`
   implements **custom, least-privilege** TGW route tables (no default
   association/propagation); `modules/tgw-attachment` creates **inert**
   attachments until topology is approved.

3. **The join point** — a **new VPN server** in the network account, linked to
   the legacy estate **via the Transit Gateway** (the legacy admin VPC is already
   a TGW attachment). **No new VPC peering is created** — this avoids a redundant
   second routing mechanism and matches ADR-0005 ("no direct VPC peering between
   workload accounts"). The security control therefore shifts entirely to the
   least-privilege custom TGW route tables. The VPN is the one component that can
   route across both estates, so it is the highest-leverage place to enforce
   segmentation.

Without an explicit model, the VPN + the legacy flat peering could create a
transitive path letting a dev/standard client reach production — exactly what
ADR-0005's segmentation promise forbids.

## Decision

Adopt a **defense-in-depth, least-privilege, deny-by-default** inter-VPC model
with four enforcement layers, applied to the new TGW estate and to the TGW join
with the legacy estate. A reviewer can check conformance by confirming every
attachment is associated with an explicit custom route table and that no route
table grants a dev/standard source a path into prod.

### Layer 1 — TGW route-table segmentation (primary control)
- **No default route-table association or propagation.** Every attachment is
  associated with an **explicit custom route table** containing **only** the
  destinations that role may reach. Production route tables **never** contain a
  route to sandbox/dev attachments.
- **VPN segmentation:** the VPN attachment's route table lists only the spokes
  VPN clients may reach; spokes get a return route to the VPN pool **only** where
  allowed. The VPN is **not** given `0.0.0.0/0` into the mesh.
- **Legacy reachability via TGW:** routes to the legacy admin/analytics ranges are
  added on the VPN route table via the legacy admin-VPC's existing attachment. The
  **return** routes on the legacy side are owned by legacy-ops (out-of-repo; see
  Consequences).

### Layer 2 — Security groups (instance/ENI control)
- Default-deny; explicit ingress only; prefer **SG references** for intra-estate
  east-west AWS sources.
- **VPN host SG:** the data-plane source is the **NLB** (target group
  `target_type = ip`, `preserve_client_ip = false`), **never `0.0.0.0/0` on the
  host**. The only world-facing surface is internet→NLB. UI restricted to admin
  networks over VPN/TGW; **no public UI**; **no SSH** (SSM only).
- DB SGs accept only the specific app/EKS SG/CIDR that the TGW route table also
  permits — SGs and TGW routes must **agree** (two independent layers).

### Layer 3 — Network ACLs (subnet backstop)
- Stateless subnet-level deny for traffic that should never appear. Prod subnets
  NACL-deny the **standard VPN sub-pool** while allowing the **ops sub-pool**, as
  a backstop behind the TGW allow-list. (Prod-account VPC unit; cross-account
  follow-up — *design-target*.)

### Layer 4 — Centralized inspection (future)
- `modules/inspection-vpc` already exists (AWS Network Firewall, TGW
  appliance-mode attachment, ALERT+FLOW logging). **Future:** route inter-segment
  / egress traffic through it for DPI + logging. Not enabled in v1.

### VPN client trust segmentation (resolved)
- The VPN pool is **sub-divided by trust level**:
  - **ops sub-pool** → full access: new prod, shared, network, and all legacy
    ranges.
  - **standard sub-pool** → **only** the shared range.
- **Only the ops sub-pool** is routed/propagated to production. The standard
  sub-pool has **no** prod route and no legacy route.
- **Negative test is an acceptance requirement:** a non-ops VPN client **must
  NOT** reach prod (verified end-to-end).

### Legacy ↔ new join rules (the critical seam)
- Link = **Transit Gateway** (legacy admin VPC already attached); **no new VPC
  peering.** The join carries **narrow, explicit routes** both ways (no broad
  supernets): new prod advertised **only to the ops segment**, not to legacy dev;
  legacy reachable from the new VPN per the allow-list (ops → all legacy;
  standard → none).
- **No transitive prod exposure:** deny-by-default TGW route tables mean a
  legacy/standard client cannot hop into prod unless an explicit allow-list entry
  permits it. The VPN allow-list is the single reviewed place this is decided.

### Detective controls
- **VPC Flow Logs** (KMS-encrypted) on the network VPC, **GuardDuty** on the
  network account, and **CloudWatch alarms** on the VPN host (EC2 auto-recovery +
  a `NetworkOut` anomaly-detection band). Required for v1.

### DNS boundary (supporting)
- The internal shared zone is a **PRIVATE** Route53 zone resolvable only inside
  associated VPCs; VPN clients resolve it via the network-VPC association + DNS
  push. The internal namespace does not leak publicly (the public apex lives
  outside AWS DNS and is untouched).

## Alternatives considered

### Alternative A: New VPC peering for the legacy join
Add a parallel VPC peering between the new network VPC and the legacy admin VPC.
Rejected because: the legacy admin VPC is already a TGW attachment; a second
routing mechanism duplicates control surface and contradicts ADR-0005. One
least-privilege control surface (the admin-VPC route table) is preferable.

### Alternative B: One flat VPN pool with broad routes
Give the whole VPN pool reachability to all estates.
Rejected because: it removes the prod-isolation guarantee — a standard client
could transit to prod. Trust sub-pools are the cheapest auditable fix.

### Alternative C: Status quo (inert attachments, no model)
Leave the TGW attachments inert and add no explicit model.
Rejected because: as soon as the VPN + legacy peering are live, an unmodelled
transitive path to prod is possible. The model must precede enabling routing.

## Consequences

### Positive
- Production stays isolated from dev/standard even with a cross-estate VPN.
- Auditable: every cross-segment flow is an explicit TGW route + SG (+ future
  firewall rule); trust sub-pools make "who can reach prod" a one-line answer.
- Incremental: the inspection VPC can be switched on later with no redesign.

### Negative
- More route-table / SG / NACL bookkeeping as accounts grow.
- The VPN allow-list + ops sub-pool membership must be change-controlled.
- The legacy flat peering mesh stays less granular than the TGW side until legacy
  VPCs are migrated onto the TGW (future).

### Risks / sequencing gate
- `enable_vpn_routing = true` must be flipped **only after** (1) the network VPC +
  attachment are applied and (2) the **prod NACL deny** backstop is in place —
  otherwise the standard sub-pool transiently reaches prod via the TGW. Default is
  `false`.

## Implementation notes

- Reuses `tgw-routing`, `tgw-attachment` (inert-by-default), `inspection-vpc`.
- Out-of-repo / cross-account follow-ups (*design-target*): legacy-side return
  routes (owned by legacy-ops), the prod NACL backstop (prod-account VPC unit),
  VPN-host egress tightening (`0.0.0.0/0:443` → VPC endpoints), enabling the
  inspection VPC for east-west, and migrating legacy peering VPCs fully onto the
  hub TGW.

## References

- AWS TGW appliance-mode / Network Firewall: <https://docs.aws.amazon.com/network-firewall/latest/developerguide/>
- Ported from `qbiq-ai/infra` ADR-012 (inter-VPC access security model)
- Related: ADR-0005 (hub-spoke TGW), ADR-0001 (OU split)

---
*Ported from qbiq-ai/infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: in-repo enforcement
adopted (live); legacy-side return routes and prod NACL backstop are
cross-account design-targets.*
