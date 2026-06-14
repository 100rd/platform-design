# ADR-0023: VPC Lattice resource connectivity for cross-account/cross-VPC TCP resource access

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — VPC Lattice resource gateway + RAM + IAM auth (#265).
- Date: 2026-06-07
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Complements: ADR-0013 (inter-VPC access security model).

## Context

The inter-VPC story today (ADR-0013) is **network-segmentation-first**:
hub-and-spoke Transit Gateway (ADR-0005) routes between VPCs, and access to a
shared resource — say an **RDS database in one account** reached from a workload in
another — is plumbed by **route tables + security groups + (often) an NLB** in
front of the database, with cross-account reach over TGW or a VPC peer. That works,
but the unit of control is **the network path (CIDRs/SGs)**, not **the identity of
the caller**, and exposing a single database cross-account still drags in an NLB and
TGW route management.

AWS **VPC Lattice** has since shipped a **resource-connectivity** model that targets
exactly this: expose an individual resource (e.g. an RDS ARN) as an
identity-scoped, IAM-authorized endpoint, reachable cross-account/cross-VPC without
standing up an NLB or threading it through Transit Gateway.

## Decision

Adopt **VPC Lattice resource connectivity** as an **identity-scoped service layer
for cross-account/cross-VPC TCP resource access**, alongside (not replacing)
ADR-0013's network model:

- Deploy a **Resource Gateway** in the resource-owning VPC — a **multi-AZ NAT-style
  ingress** that fronts the shared resource.
- Define a **Resource Configuration** of **`type = ARN`** pointing at the target
  resource ARN (e.g. an **RDS DB ARN**).
- Associate the Resource Configuration to a **Service Network**.
- Share the Service Network cross-account via **AWS RAM (Resource Access Manager)**.
- The **consumer** reaches the resource through a **service-network VPC
  association / endpoint** in its own VPC.
- Authorization is enforced with **IAM auth policies** on the service network /
  resource (`vpc-lattice:*` actions) — so access is **identity-scoped**, not just
  CIDR/SG-scoped.

This **bypasses the NLB** in front of the resource and, **intra-region, bypasses
Transit Gateway** for that resource flow.

A reviewer can check conformance by confirming a Resource Gateway exists in the
owning VPC, a `type = ARN` Resource Configuration points at the RDS DB ARN,
the service network is shared via RAM, the consumer reaches it via a
service-network VPC association/endpoint, and access is gated by `vpc-lattice:*`
IAM auth policies.

## Alternatives considered

### Alternative A: Status quo — NLB + TGW + security groups (ADR-0013 only)
Keep fronting shared resources with an NLB and routing cross-account over TGW with
SG/CIDR control.
Rejected as the default for *resource* sharing because: the control unit is the
network path, not caller identity; exposing one database cross-account still needs
an NLB and TGW route plumbing. VPC Lattice resource connectivity makes the unit of
control the **IAM identity** and drops the NLB/TGW from that specific flow.

### Alternative B: VPC peering / PrivateLink endpoint services per resource
Stand up PrivateLink endpoint services or peer the VPCs.
Rejected because: PrivateLink endpoint services still require an NLB behind them and
scale awkwardly per-resource; peering is a full-mesh routing burden. Lattice's
service-network + RAM model centralizes the sharing and adds IAM authz.

### Alternative C: Lattice for *everything* inter-VPC
Replace ADR-0013's TGW segmentation with VPC Lattice wholesale.
Rejected because: VPC Lattice resource connectivity is **TCP-only** and
**single-region only** — it cannot carry non-TCP traffic or cross-region flows, and
it is an identity-scoped *service* layer, not a general network fabric. It
**complements** ADR-0013 for resource access; the TGW segmentation stays the
general inter-VPC substrate.

## Consequences

### Positive
- Cross-account/cross-VPC resource access becomes **identity-scoped** (IAM auth
  policies), not just network-scoped.
- **No NLB** in front of the shared resource; **intra-region TGW bypass** for that
  flow.
- Centralized sharing via Service Network + RAM rather than per-pair peering.
- Complements ADR-0013 cleanly — different unit of control (identity vs path).

### Negative
- A new connectivity primitive (Resource Gateway / Resource Configuration / Service
  Network) to operate and reason about alongside TGW.
- IAM auth policies add a second authorization surface to keep consistent with SGs.

### Risks
- **TCP-only, single-region-only** limits — a non-TCP or cross-region resource flow
  must stay on the ADR-0013 path. Mitigated by scoping Lattice to in-region TCP
  resource sharing only.
- A permissive `vpc-lattice:*` auth policy could over-share a resource. Mitigated by
  least-privilege auth policies scoped to specific consumer principals.

## Implementation notes

- Files / modules touched: a new `modules/vpc-lattice-resource` (Resource Gateway +
  Resource Configuration `type = ARN` + Service Network + RAM share + auth policy);
  consumer-side VPC association/endpoint.
- Migration: introduce per shared resource (start with one RDS DB); keep the
  existing ADR-0013 path until the Lattice path is validated, then cut the consumer
  over.
- Rollback: detach the service-network association and point the consumer back at
  the ADR-0013 NLB/TGW path.
- CI/test: validate the Resource Configuration ARN and the IAM auth policy in
  `terraform-checks`.

Effort: **M**.

## References

- VPC Lattice resource configurations / resource gateway:
  <https://docs.aws.amazon.com/vpc-lattice/latest/ug/resource-configuration.html>
- VPC Lattice cross-account sharing with RAM:
  <https://docs.aws.amazon.com/vpc-lattice/latest/ug/sharing.html>
- VPC Lattice IAM auth policies:
  <https://docs.aws.amazon.com/vpc-lattice/latest/ug/auth-policies.html>
- Related: ADR-0013 (inter-VPC access security model), ADR-0005 (Transit Gateway)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
