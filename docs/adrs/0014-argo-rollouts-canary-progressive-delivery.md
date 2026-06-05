# ADR-0014: Argo Rollouts canary with Gateway API traffic-routing and analysis

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

Platform workloads on EKS (the inference-gateway front-end, render/document
services, public APIs) need a deployment strategy that limits the blast radius of
a bad release. A plain Kubernetes `Deployment` rolling update shifts all traffic
to new pods as they become Ready, with no metric-gated pause — a regression in
error rate or p95 latency is only caught after it is already serving production
traffic. Options:

1. **Plain `Deployment` rolling update** — simple, but no progressive traffic
   shift and no automated metric gate.
2. **Argo Rollouts canary** — weighted traffic shift with analysis-gated steps,
   integrated with ArgoCD (ADR-0006).
3. **Manual blue/green via two Services** — operator-driven, error-prone.

The platform already runs ArgoCD (ADR-0006) and Cilium Gateway API (ADR-0009),
and ships a Prometheus stack — the prerequisites for metric-gated canary.

## Decision

Use **Argo Rollouts** with a **canary** strategy for production workloads via the
shared `qbiq-app` Helm chart. Traffic is shifted by the **Gateway API plugin**
(`argoproj-labs/gatewayAPI`) adjusting `HTTPRoute` backend weights between a
stable and a canary Service; each weight step is gated by an inline **Analysis**
(Prometheus `error-rate` and `latency-p95` queries against the canary Service
only).

A reviewer can check conformance by confirming production workloads are authored
as `Rollout` objects with a canary strategy + `AnalysisTemplate`, not bare
`Deployment` rolling updates.

## Alternatives considered

### Alternative A: Plain Deployment rolling update
Use Kubernetes-native rolling updates.
Rejected because: no weighted traffic control and no automated metric gate — a
latency or error-rate regression is served to 100% of traffic before anyone
notices. Unacceptable for the latency-sensitive scoring/gateway path.

### Alternative B: Manual blue/green
Stand up a second Service and cut over manually.
Rejected because: it is operator-driven and error-prone, with no automated
abort-on-bad-metrics. Argo Rollouts encodes the same idea declaratively with
analysis gating.

### Alternative C: Status quo (Deployment)
Same as Alternative A — rejected for the same reasons.

## Consequences

### Positive
- Weighted canary: `canaryService` receives a controlled fraction while
  `stableService` keeps the rest; the Gateway API plugin (ADR-0009) drains
  connections gracefully on each shift.
- Metric-gated steps: inline `AnalysisTemplate` checks Prometheus `error-rate`
  and `latency-p95` (against the canary Service only) before advancing.
- Graceful abort: on analysis failure the canary ReplicaSet stays alive for
  `abortScaleDownDelaySeconds` so in-flight requests complete, then rolls back.
- Reuses the existing ArgoCD + Gateway API + Prometheus stack — no new platform
  dependency.

### Negative
- Workloads are authored as `Rollout` CRDs, not `Deployment` (chart abstracts
  most of this).
- Requires a canary Service and `HTTPRoute` wiring per workload (provided by the
  shared chart).
- Analysis queries must be tuned per workload (interval, count, `failureLimit`,
  success conditions) or canaries either stall or pass bad releases.

### Risks
- A mis-specified Prometheus query (e.g. counting stable traffic) would gate on
  the wrong signal. Mitigated by the chart passing the canary Service name into
  the analysis args so queries target only canary traffic.
- Rollouts controller is another component to operate. Mitigated by GitOps-managed
  install and pinning.

## Implementation notes

- Shared chart `qbiq-app` templates: `rollout.yaml` (canary steps +
  `trafficRouting.plugins.argoproj-labs/gatewayAPI`), `analysistemplate.yaml`
  (`error-rate`, `latency-p95`), `service-canary.yaml`, `httproute.yaml`.
- Canary weights and analysis parameters are chart values per workload; analysis
  is opt-in via `rollout.analysis.enabled`.

## References

- Argo Rollouts: <https://argo-rollouts.readthedocs.io/>
- Gateway API plugin: <https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi>
- Ported from `qbiq-ai/argocd` (`charts/qbiq-app` rollout + analysistemplate)
- Related: ADR-0006 (ArgoCD), ADR-0009 (Cilium Gateway API)

---
*Ported from qbiq-ai/infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
