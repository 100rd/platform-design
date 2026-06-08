# Pyrra — SLO Operator (ADR-0026)

## Provenance

Implements the **SLO slice** of [ADR-0026](../../../docs/adrs/0026-observability-target-architecture.md).

**Decision**: Pyrra was chosen over Sloth because it ships a **built-in UI** (SLO
detail pages + multi-window error-budget burn charts) in addition to emitting
`PrometheusRule` objects.  Sloth is a pure CLI generator — useful for CI-only
pipelines, but provides no runtime visibility.  The team wanted a single `kubectl
apply` to get both the rules and the UI.  See ADR-0026 §Decision for the full
either/or framing.

## What this chart does

1. Deploys the **Pyrra operator** (kubernetes mode) — watches `ServiceLevelObjective`
   CRs and generates matching `PrometheusRule` objects.
2. Deploys the **Pyrra UI/API** — queries Prometheus and serves SLO status pages on
   port 9099.
3. Provides two example `ServiceLevelObjective` CRs:
   - `api-availability` — 99.9 % success rate (28-day window)
   - `api-latency-p99` — 99 % of requests under 500 ms (28-day window)

## Native Histograms

The latency SLO CR references `http_request_duration_seconds_bucket` (classic
histogram format).  Once Prometheus native-histogram scraping is active (enabled in
`../observability/prometheus-stack/values.yaml` per ADR-0026), Pyrra will
automatically prefer the `nhcb()` representation for improved accuracy.

## Deployment

```bash
# Wire the ArgoCD Application
kubectl apply -f argocd-application.yaml

# Or install directly via Helm (dev/test only)
helm dependency update .
helm upgrade --install pyrra . -n observability --create-namespace -f values.yaml
```

## Adding SLOs

Create a `ServiceLevelObjective` CR in any namespace; the Pyrra operator will pick
it up and emit the appropriate `PrometheusRule`.  See
[templates/slo-availability.yaml](templates/slo-availability.yaml) and
[templates/slo-latency.yaml](templates/slo-latency.yaml) for examples.

## References

- Pyrra: <https://github.com/pyrra-dev/pyrra>
- ADR-0026: `docs/adrs/0026-observability-target-architecture.md`
- Related epic: #252
