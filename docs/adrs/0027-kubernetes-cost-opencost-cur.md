# ADR-0027: Kubernetes cost allocation via OpenCost + AWS CUR/Athena cloud-integration

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — OpenCost + CUR/Athena cost export (#257).
- Date: 2026-06-07
- Authors: platform-team, finops
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

There is no per-namespace / per-workload **cost** signal today. AWS billing stops at
the account/tag level; it cannot say "namespace X cost $Y this week" or attribute a
shared node's cost across the pods on it. And naive Kubernetes cost tools price
against **on-demand list rates**, which **overstates** real spend on an estate that
runs **Reserved Instances / Savings Plans / Spot** — the bill is **discounted and
amortized**, so allocation must reconcile to the *actual billed* cost, not list
price.

## Decision

Adopt **OpenCost (CNCF Incubating)** for in-cluster cost allocation, reconciled to
real AWS billing via the **AWS CUR/Athena cloud-integration**:

- **OpenCost** allocates cost **per namespace / workload / label**, splitting shared
  node cost across the pods that run on it.
- The **AWS CUR/Athena cloud-integration** grounds allocation in the real bill:
  - **Cost and Usage Report (CUR)** delivered to **S3**,
  - a **Glue database** over it,
  - an **Athena workgroup** to query it,
  - **IAM** for OpenCost to read it,
  - all surfaced to OpenCost via the **`cloud-integration.json` secret**.
- Allocation is reconciled to the **amortized, discount-aware billed cost**
  (**RIs / Savings Plans / Spot**) — **not on-demand list pricing** — so the numbers
  match the invoice.

**Evolutionary adoption (not a big bang):**
- **Start** with **OpenCost + CUR** (the open, sufficient base).
- **Optionally** layer **Kubecost Free** (built on OpenCost) for its **UI +
  right-sizing recommendations** — bounded at **≤ 250 cores** and **15-day
  retention**.
- **Kubecost Enterprise** only if/when **long retention**, **multi-cluster
  aggregation**, or **RBAC** are actually required.

A reviewer can check conformance by confirming OpenCost is deployed, the CUR → S3 →
Glue → Athena → IAM chain exists and is wired via `cloud-integration.json`, that
allocation reflects **amortized/discounted** cost (RIs/SPs/Spot, not list price), and
that any Kubecost layer is the Free tier within the 250-core / 15-day bounds unless
Enterprise was explicitly justified.

## Alternatives considered

### Alternative A: Status quo — AWS Cost Explorer / tags only
Rely on account- and tag-level AWS billing.
Rejected because: it cannot allocate a shared node's cost across pods, gives no
per-namespace/workload view, and offers no in-cluster right-sizing signal.

### Alternative B: OpenCost with on-demand list pricing (no CUR integration)
Run OpenCost but skip the CUR/Athena reconciliation.
Rejected because: list-price allocation **overstates** spend on an RI/SP/Spot estate
— the allocation would not match the invoice, undermining trust in the numbers. The
CUR integration is what makes it amortized and discount-aware.

### Alternative C: Kubecost Enterprise from day one
Buy the Enterprise tier up front.
Rejected because: OpenCost + CUR already delivers discount-aware per-workload
allocation; Kubecost Free adds the UI/right-sizing within generous bounds. Enterprise
is only justified by long retention / multi-cluster / RBAC needs we do not have yet —
adopt evolutionarily.

## Consequences

### Positive
- Per-namespace / workload / label cost allocation, shared-cost split.
- Numbers reconcile to the **real, discounted, amortized** bill (RIs/SPs/Spot).
- Evolutionary: open base (OpenCost+CUR) → optional Kubecost Free UI/right-sizing →
  Enterprise only on demonstrated need.

### Negative
- The CUR/Athena/Glue/IAM chain is real plumbing to stand up and keep current.
- Cost data lags the bill (CUR delivery cadence) — near-real-time, not instant.

### Risks
- A mis-scoped IAM/`cloud-integration.json` exposing billing data. Mitigated by
  least-privilege read-only Athena/Glue/S3 access and storing the secret via ESO
  (ADR-0008).
- Allocation drift if CUR/Glue schema changes. Mitigated by pinning the integration
  and validating reconciliation against a known invoice.
- Outgrowing Kubecost Free bounds (250 cores / 15-day) silently. Mitigated by
  alerting on the bound and an explicit Enterprise decision when crossed.

## Implementation notes

- Files / modules touched: a `modules/cur-athena` (CUR + S3 + Glue DB + Athena
  workgroup + IAM) and the OpenCost install (GitOps-managed) consuming
  `cloud-integration.json` (delivered via ESO from Secrets Manager, ADR-0008).
- Migration: stand up CUR/Athena first, deploy OpenCost pointing at it, validate
  amortized allocation against an invoice, then optionally add Kubecost Free.
- Rollback: remove OpenCost/Kubecost; the CUR/Athena data remains for AWS-side
  analysis.
- CI/test: terraform-checks over the CUR/Athena module; manifest-validate (ADR-0016)
  over the OpenCost values.

Effort: **L**.

## References

- OpenCost: <https://www.opencost.io/docs/>
- OpenCost AWS cloud-integration (CUR/Athena):
  <https://www.opencost.io/docs/configuration/aws>
- AWS Cost and Usage Report (CUR):
  <https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html>
- Kubecost (Free vs Enterprise tiers):
  <https://docs.kubecost.com/install-and-configure/install>
- Related: ADR-0008 (External Secrets Operator — delivers `cloud-integration.json`),
  ADR-0007 (Karpenter — Spot/right-sizing context)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
