# ADR-0005: Hub-and-spoke connectivity via AWS Transit Gateway

- Status: **Accepted** — decision is *adopted (live in source estate)*
- platform-design status: **synced** — TGW hub-and-spoke modules present
  (`terraform/modules/transit-gateway`, `tgw-attachment`, `tgw-peering`);
  network-account connectivity stack wires them.
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

With many AWS accounts (ADR-0001) each containing one or more VPCs, the platform
needs an inter-VPC connectivity strategy that scales and supports segmentation —
production data-plane traffic must never have a route to sandbox/dev. Options
evaluated:

1. **VPC peering** — point-to-point connections.
2. **AWS Transit Gateway (TGW)** — hub-and-spoke.
3. **AWS Cloud WAN** — managed global network.

The platform is anchored in `eu-west-1` for the primary control plane (with
additional EU regions for the multi-region tier), so a single-region-optimised
topology is acceptable for v1.

## Decision

Use **AWS Transit Gateway** in a hub-and-spoke topology, owned and managed from
the **Network account**. Inter-VPC routing is expressed through custom TGW route
tables (no default association/propagation), so reachability is an explicit
allow-list.

A reviewer can check conformance by confirming new VPC attachments go through the
TGW (not a new peering connection) and are associated with an explicit custom
route table.

## Alternatives considered

### Alternative A: VPC peering mesh
Peer every VPC that needs to talk to every other.
Rejected because: peering is non-transitive and grows as N·(N-1)/2 — unmanageable
at the platform's account count, and segmentation (prod ↛ sandbox) becomes a
per-pair bookkeeping exercise instead of a route-table policy.

### Alternative B: AWS Cloud WAN
Managed global network with policy-based segmentation.
Rejected because: Cloud WAN's value is multi-region global routing; for a
single-region-anchored estate it is more expensive than TGW with no offsetting
benefit. Revisit if the estate becomes genuinely global-mesh.

### Alternative C: Status quo
At decision time the estate was greenfield — "status quo" is no shared
connectivity, which does not meet the requirement.

## Consequences

### Positive
- Scales to thousands of attachments; no peering combinatorics.
- Centralised routing and a single point for future traffic inspection (a
  centralised inspection VPC with AWS Network Firewall — see ADR-0013).
- Custom TGW route tables provide network segmentation: production route tables
  never contain a route to sandbox/dev attachments.
- Hub VPC in the Shared account offers centralised endpoints (DNS, ECR, S3
  gateway) reachable from all spokes.
- More cost-effective than Cloud WAN for the platform's single-region anchor.

### Negative
- TGW hourly charge per attachment (~$36/month per VPC attachment).
- Data-processing charges for inter-VPC traffic through the TGW.
- Route-table management grows more complex as account count grows.

### Risks
- TGW as a single point of failure. Mitigated by TGW's multi-AZ design.
- Cross-region connectivity needs a second TGW with peering. Tracked as a
  future-consideration for the multi-region tier, not v1.

## Implementation notes

- `modules/transit-gateway` + `modules/tgw-routing` + `modules/tgw-attachment`
  (attachments inert by default until routes are added).
- Owned by the Network account; route tables are custom, least-privilege.
- The detailed cross-estate / VPN segmentation model layered on this is ADR-0013.

## References

- AWS Transit Gateway: <https://docs.aws.amazon.com/vpc/latest/tgw/>
- Ported from `infra` ADR-003 (Hub-and-spoke via Transit Gateway)
- Related: ADR-0001 (OU split), ADR-0013 (inter-VPC access security model)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
