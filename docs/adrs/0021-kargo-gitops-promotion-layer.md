# ADR-0021: Kargo as the GitOps environment-promotion layer

- Status: **Proposed** — research-backed; decision to ratify, not yet
  implemented.
- platform-design status: **pending** — Kargo is scaffolded (Warehouse → Stage →
  Freight graph) but not activated; the bootstrap App pins the old chart.
- Date: 2026-06-06
- Authors: platform-team
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

The estate already **scaffolds Kargo**: a full **Warehouse → Stage → Freight**
promotion graph for **5 projects × 4 environments**, a `kargo-bootstrap.yaml`
App, and the chart **pinned to 1.2.0**. Kargo has since reached **GA (v1.9)**, so
the scaffold is well behind a stable release.

The promotion problem it solves is real: today environment promotion is implicit in
how ArgoCD Applications are pointed at branches/paths, with **job-probe**
verification gates (a one-shot probe Job) rather than metric analysis.

**IMPORTANT — what Kargo sits above here:** there is **no Argo Rollouts in this
repo**. (ADR-0014 ports the *concept* from the source estate, but no Rollout CRD is
deployed in platform-design.) So Kargo promotes **Argo CD Applications directly** —
it is the layer that advances Freight from environment to environment, **not** a
layer sitting above Argo Rollouts canaries.

## Decision

**Activate Kargo as the environment-promotion layer:**

- **Bump the pin 1.2.0 → 1.9** via the existing `kargo-bootstrap.yaml` (no new
  bootstrap machinery — the App already exists).
- **Keep the existing promotion graph**:
  `dev (auto)` → `integration` → `staging` → `prod (manual, by digest)`. Dev
  auto-promotes; prod requires a manual, digest-pinned promotion.
- **Author Prometheus-provider `AnalysisTemplate`s** for **5xx rate** and **p95
  latency** to **upgrade the current job-probe verification gates** into
  metric-gated promotion. These metrics are sourced from **Tempo's
  metrics-generator RED metrics** — which **couples this ADR to ADR-0019** (the OBI/
  Beyla → Tempo wiring is what produces those RED metrics; without 0019 the gates
  have nothing to read).

A **separate future ADR may introduce Argo Rollouts canary BELOW Kargo** (Kargo
promotes between environments; a Rollout would canary *within* an environment).
That is explicitly out of scope here.

A reviewer can check conformance by confirming the Kargo chart is pinned to 1.9
via `kargo-bootstrap.yaml`, the dev-auto → integration → staging → prod-manual/
digest Stage graph is intact, and that promotion gates use Prometheus
`AnalysisTemplate`s (5xx / p95) reading Tempo RED metrics rather than the old
job-probe.

## Alternatives considered

### Alternative A: Keep manual / branch-pointer promotion (status quo)
Leave Kargo scaffolded-but-off and promote by repointing Applications.
Rejected because: promotion stays implicit and un-gated on metrics; the scaffold
(5×4 graph already authored) is wasted, and the pin drifts further from GA.

### Alternative B: Activate Kargo but keep job-probe gates
Turn Kargo on without the Prometheus AnalysisTemplates.
Rejected because: a one-shot probe Job proves "it responded once", not "5xx and p95
are healthy under traffic". The RED-metric gates (from ADR-0019's Tempo feed) are
the actual safety signal.

### Alternative C: Put Kargo above Argo Rollouts now
Introduce Rollouts and stack Kargo on top in this ADR.
Rejected because: **no Rollout exists in this repo** — introducing canary-within-an-
environment is a distinct decision with its own trade-offs. Keep this ADR to the
environment-promotion layer; a future ADR can add Rollouts below.

## Consequences

### Positive
- Explicit, auditable environment promotion (Warehouse → Stage → Freight) at GA.
- Metric-gated promotion (5xx / p95) replaces one-shot job probes.
- Reuses the already-authored 5×4 graph and the existing bootstrap App.
- Digest-pinned, manual prod promotion keeps a human gate on production.

### Negative
- Kargo is another control-plane component to operate and keep pinned.
- Promotion gates now depend on ADR-0019 being live (Tempo fed with RED metrics).

### Risks
- **Coupling to ADR-0019:** if the Tempo RED-metrics feed is absent, the
  AnalysisTemplates have no data and gates fail open/closed. Mitigated by
  sequencing 0019 before flipping gates from job-probe to metric.
- A 1.2 → 1.9 bump spans several releases — CRD/schema migration risk. Mitigated by
  staging the bump in a non-prod project first.
- Mis-tuned 5xx/p95 thresholds stall or wave through promotions. Mitigated by
  per-Stage tuning starting permissive in dev.

## Implementation notes

- Edit `kargo-bootstrap.yaml` to pin the chart at **1.9**; GitOps-managed.
- Keep the Stage graph: `dev` (auto) → `integration` → `staging` → `prod`
  (manual promotion, by digest).
- Add Prometheus-provider `AnalysisTemplate`s: `error-rate` (5xx) and
  `latency-p95`, querying Tempo metrics-generator RED metrics (ADR-0019).
- Replace the job-probe verification on each Stage with the AnalysisTemplate gate.
- Out of scope / future ADR: Argo Rollouts canary **below** Kargo.

Effort: **M**.

## References

- Kargo: <https://docs.kargo.io/>
- Kargo verification / AnalysisTemplates:
  <https://docs.kargo.io/concepts#verifications>
- Related: ADR-0006 (ArgoCD — Kargo promotes its Applications), ADR-0019 (Tempo RED
  metrics feeding the gates), ADR-0014 (Argo Rollouts — concept; a future ADR may
  place Rollouts below Kargo)

---
*Research-backed — 2026 platform modernization; grounded in infra@572b54d /
argocd@c364c6c. Proposed: decision to ratify, not yet implemented in
platform-design.*
