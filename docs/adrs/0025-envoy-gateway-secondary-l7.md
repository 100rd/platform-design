# ADR-0025: Envoy Gateway as a secondary L7 GatewayClass alongside Cilium

- Status: **Accepted** — research-backed + doc-verified; ratified, not yet
  implemented.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **pending** — only the Cilium Gateway API GatewayClass
  (ADR-0009) is present; no Envoy Gateway GatewayClass is deployed.
- Date: 2026-06-07
- Authors: platform-team
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Extends: ADR-0009 (Cilium Gateway API as cluster ingress).

## Context

Cluster ingress today is **Cilium Gateway API** (ADR-0009) — one GatewayClass,
backed by the Cilium/Envoy data plane, NLB-fronted. Cilium's Gateway API
implementation covers the standard L7 routing surface, but a few **advanced L7
capabilities** are either missing or immature there:

- **Global (cross-replica) rate limiting.**
- **External processing (`ext-proc`)** — the hook the **Gateway API Inference
  Extension / AI-gateway** patterns rely on.
- **WASM** filter extensibility.
- **Circuit breaking.**

We need these for specific services (notably AI/inference routing) without
abandoning Cilium, which remains the CNI and the primary ingress.

## Decision

Adopt **Envoy Gateway (target v1.8.x)** as a **secondary GatewayClass running
alongside Cilium**, used **only** for the advanced L7 features Cilium Gateway API
lacks:

- **Global rate limiting**, **`ext-proc`** (Gateway API Inference Extension /
  AI-gateway), **WASM**, and **circuit breaking**.

**Cilium stays the CNI and the primary ingress.** Envoy Gateway brings its **own
Envoy data plane**, **is not a CNI**, and therefore **does not conflict** with
Cilium — the two GatewayClasses coexist, and a route picks the class that has the
capability it needs. Standard routing stays on the Cilium GatewayClass (ADR-0009);
only routes that need the advanced features above target the Envoy Gateway class.

A reviewer can check conformance by confirming an Envoy Gateway GatewayClass exists
**in addition to** the Cilium one, that Cilium remains the CNI/primary ingress, and
that only advanced-L7 routes (rate limit / ext-proc / WASM / circuit breaking) bind
to the Envoy Gateway class.

## Alternatives considered

### Alternative A: Status quo — Cilium Gateway API only
Keep a single GatewayClass and live without the advanced L7 features.
Rejected because: global rate limiting, `ext-proc` (the AI-gateway hook), WASM, and
circuit breaking are real requirements for some services and are not available (or
not mature) on the Cilium GatewayClass today.

### Alternative B: AWS Load Balancer Controller Gateway API v3.0 — **CANDIDATE** (not accepted)
LBC Gateway API **v3.0 (GA 2026-01-23)** offers an **ALB GatewayClass**
(`gateway.k8s.aws/alb`) and an **NLB GatewayClass** (`gateway.k8s.aws/nlb`) that
**coexist with Cilium**.
**Marked CANDIDATE, not accepted, because:** we run **NLB-only** today, and **Argo
Rollouts' AWS-native canary is ALB-Ingress-based, not Gateway-API-based** — so
adopting the ALB GatewayClass now would not slot into the existing canary path.
**Revisit when ALB enters** the estate (then the ALB GatewayClass + Rollouts ALB
integration become coherent).

### Alternative C: GAMMA on Cilium for east-west — **CANDIDATE** (not accepted)
Use the **GAMMA** initiative (Gateway API for service mesh) on Cilium to route
**east-west** traffic (`HTTPRoute` → `Service`). Cilium supports **GAMMA v1.0.0**
(**Core + 2/3 Extended**), but **producer-only / same-namespace**, with **no
consumer routes**, and it is **experimental**.
**Marked CANDIDATE, not accepted, because:** the producer-only/same-namespace,
no-consumer-route, experimental constraints make it premature to standardize on for
east-west routing now. Revisit as Cilium's GAMMA support matures.

### Alternative D: Replace Cilium ingress with Envoy Gateway wholesale
Make Envoy Gateway the single GatewayClass.
Rejected because: that throws away the Cilium-native ingress (ADR-0009) and its CNI
integration for no benefit on standard routes. Envoy Gateway is **additive** for the
advanced-L7 gap only.

## Consequences

### Positive
- Unlocks global rate limiting, `ext-proc`/AI-gateway, WASM, and circuit breaking
  without leaving Cilium.
- No CNI conflict — Envoy Gateway has its own data plane and coexists with Cilium.
- Standard routing stays on the proven Cilium GatewayClass; only advanced routes move.

### Negative
- A second GatewayClass + Envoy Gateway control plane to operate and pin.
- Route authors must know which class to target for which capability.

### Risks
- Two ingress data planes drifting in config/version. Mitigated by GitOps-managing
  both and pinning Envoy Gateway to v1.8.x.
- Capability sprawl onto the Envoy class. Mitigated by the rule: Envoy class **only**
  for rate-limit / ext-proc / WASM / circuit-breaking; everything else stays Cilium.

## Implementation notes

- Files / modules touched: a new Envoy Gateway install (GitOps-managed, pinned
  v1.8.x) + its GatewayClass; HTTPRoutes for advanced-L7 services point at it.
- Migration: deploy Envoy Gateway class alongside Cilium; move only the
  advanced-L7 routes; leave ADR-0009 routes untouched.
- Rollback: delete the Envoy GatewayClass + routes; advanced features revert to
  unavailable (services fall back to Cilium routing).
- Candidates tracked separately: AWS LBC Gateway API v3.0 (revisit on ALB),
  GAMMA-on-Cilium (revisit as it matures).

Effort: **M**.

## References

- Envoy Gateway: <https://gateway.envoyproxy.io/docs/>
- Gateway API Inference Extension (ext-proc / AI gateway):
  <https://gateway-api-inference-extension.sigs.k8s.io/>
- AWS Load Balancer Controller Gateway API (v3.0):
  <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/>
- GAMMA (Gateway API for service mesh) on Cilium:
  <https://docs.cilium.io/en/stable/network/servicemesh/gamma/>
- Related: ADR-0009 (Cilium Gateway API ingress), ADR-0003 (Cilium CNI),
  ADR-0014 (Argo Rollouts canary — ALB-Ingress-based today)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
