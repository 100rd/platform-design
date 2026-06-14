# ADR-0026: Observability target architecture (LGTM-aligned: Prometheus 3 + Thanos, Loki, Tempo, Alloy)

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — Prometheus 3.x + Thanos + Loki/Alloy + Tempo/OBI + Pyrra (#261/#275).
- Date: 2026-06-07
- Authors: platform-team
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Builds on: ADR-0019 (OBI/Beyla → Tempo), ADR-0021 (Prometheus analysis gates).

## Context

Observability has grown piecemeal — Prometheus here, Tempo deployed-but-unfed
(ADR-0019), Grafana dashboards, ad-hoc log shipping — without a single ratified
target. Without one, every new signal invites a fresh tool, and several tempting
"all-in-one" or "next-gen" options are actually **rip-and-replace** of a tier we
already run, not additions. This ADR ratifies a **coherent LGTM-aligned target** and
explicitly records the **either/or** boundaries so the estate does not end up paying
for two overlapping long-term tiers.

## Decision

Ratify the following target, signal by signal:

- **Metrics:** **Prometheus 3.x** — **native histograms** are **stable as of 3.8**;
  the **OTLP receiver ships off-by-default** (enable deliberately). Long-term
  storage stays **Thanos on S3**. **STAY on Thanos; do NOT adopt Mimir** — Mimir is
  an **either/or rip-and-replace of the same long-term tier**, not an addition.
- **Logs:** **Loki**, shipped by **Alloy**.
- **Pipeline hub:** **Alloy** — Alloy **is Grafana's distribution of the OTel
  Collector**, so **do NOT run a separate upstream OTel Collector**; that would be
  redundant with Alloy.
- **Traces:** **Tempo + OBI/Beyla** (additive, per ADR-0019). **Pick ONE RED-metric
  source** — **either** OBI **or** Tempo's metrics-generator, **not both** (double
  RED metrics = double cost + reconciliation pain). **OBI is alpha → pilot it.**
- **Profiles:** **Pyroscope 2.0** — **DEFER.** The **OpenTelemetry Profiles signal
  is Alpha**; revisit when it stabilizes.
- **SLO:** adopt **one of Pyrra** (built-in UI) **or Sloth** (generator-only) — both
  **emit `PrometheusRule`s** (recording/alerting). Choose by whether the built-in UI
  is wanted (Pyrra) or pure generation suffices (Sloth).
- **Dashboards:** **Grafana** primary; **Perses** optional for
  **dashboards-as-code**.
- **Do NOT add Coroot** — an all-in-one eBPF APM that **overlaps the entire LGTM
  stack**; it is **either/or, not additive**, so adding it duplicates metrics/logs/
  traces tiers we already run.

A reviewer can check conformance by confirming Prometheus is 3.x (native histograms
on, OTLP receiver deliberately set), Thanos (not Mimir) is the long-term tier, Loki
+ Alloy carry logs, **no separate upstream OTel Collector** runs beside Alloy,
exactly **one** RED-metric source is enabled, Pyroscope is deferred, one of
Pyrra/Sloth emits the SLO PrometheusRules, and Coroot is absent.

## Alternatives considered

### Alternative A: Status quo — piecemeal, no ratified target
Keep adding tools per signal without a target architecture.
Rejected because: it is exactly how overlapping long-term tiers and redundant
collectors creep in; a ratified target makes "additive vs rip-and-replace" an
explicit gate.

### Alternative B: Mimir instead of Thanos for the long-term metrics tier
Replace Thanos with Grafana Mimir.
Rejected because: Mimir and Thanos are the **same tier** — adopting Mimir is a
rip-and-replace migration of working long-term storage for no net capability we need.
Stay on Thanos.

### Alternative C: A separate upstream OTel Collector alongside Alloy
Run the upstream OpenTelemetry Collector as the pipeline hub.
Rejected because: **Alloy is Grafana's OTel Collector distribution** — running both
is redundant. Alloy is the single pipeline hub.

### Alternative D: Coroot as an all-in-one eBPF APM
Adopt Coroot for unified eBPF observability.
Rejected because: it **overlaps the entire LGTM stack** (metrics/logs/traces) — it
is an either/or replacement, not an additive layer, and would duplicate tiers we
already operate.

### Alternative E: Adopt Pyroscope 2.0 profiling now
Turn on continuous profiling immediately.
Rejected (deferred) because: the **OpenTelemetry Profiles signal is Alpha**; defer
until it stabilizes to avoid churning on a moving spec.

## Consequences

### Positive
- One coherent LGTM-aligned target; "additive vs replace" is an explicit decision.
- Avoids two overlapping long-term metrics tiers (Thanos kept, Mimir rejected).
- Single pipeline hub (Alloy) — no redundant collector.
- Exactly one RED-metric source — no double-counting/cost.
- SLOs as code via Pyrra/Sloth → PrometheusRules.

### Negative
- A multi-component stack to operate and pin; phased rollout needed.
- Native-histogram migration and the OTLP-receiver toggle are deliberate config
  steps, not defaults.

### Risks
- Enabling **both** OBI and Tempo metrics-generator by accident → double RED metrics.
  Mitigated by the explicit "pick one" conformance check.
- Native-histogram cutover changing dashboard/query semantics. Mitigated by staging
  on non-prod first.
- Scope creep toward Mimir/Coroot under feature pressure. Mitigated by recording them
  as rejected either/or alternatives here.

## Implementation notes

- Files / modules touched: observability Helm values (Prometheus 3.x + native
  histograms, Thanos, Loki, Alloy, Tempo), SLO generator (Pyrra **or** Sloth),
  optional Perses.
- Phasing: (1) Prometheus 3.x + Thanos baseline; (2) Loki + Alloy logs, Alloy as the
  single hub; (3) Tempo fed via ADR-0019 OBI/Beyla, choose the one RED source;
  (4) SLO generator → PrometheusRules; (5) defer Pyroscope; never add Coroot/Mimir.
- Rollback: each signal's component is independently revertible to the prior shipper.
- CI/test: manifest-validate (ADR-0016) over the observability values.

Effort: **phased** (multi-step; no single big-bang).

## References

- Prometheus native histograms (stable 3.8) / OTLP receiver:
  <https://prometheus.io/docs/specs/native_histograms/>
- Thanos: <https://thanos.io/>
- Grafana Alloy (OTel Collector distribution):
  <https://grafana.com/docs/alloy/latest/>
- Loki: <https://grafana.com/docs/loki/latest/>; Tempo:
  <https://grafana.com/docs/tempo/latest/>
- Pyrra: <https://github.com/pyrra-dev/pyrra>; Sloth: <https://sloth.dev/>
- OpenTelemetry Profiles signal (Alpha):
  <https://opentelemetry.io/docs/specs/otel/profiles/>
- Related: ADR-0019 (OBI/Beyla → Tempo), ADR-0021 (Prometheus analysis gates)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
