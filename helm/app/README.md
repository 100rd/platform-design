# Generic Application Chart

This Helm chart deploys a generic application container with optional Nginx ingress and integration with the External Secrets Operator using AWS as the backend.

## Features

- Deployment **or** Argo Rollouts canary (`rollout.enabled` toggle) — mutually exclusive workload kinds sharing one pod spec.
- Service resource, plus an optional weighted **canary Service** for progressive delivery.
- Optional Ingress resource supporting multiple ingress classes (e.g., `nginx`, `internal-nginx`).
- Optional Gateway API `HTTPRoute` for internal ingress and canary traffic shifting.
- Optional ExternalSecret resource to fetch secrets from AWS Secrets Manager via External Secrets Operator.

## Workload kind: Deployment vs Argo Rollouts canary

By default (`rollout.enabled: false`) the chart renders a plain `Deployment` — this
is backward compatible, so existing releases are unaffected.

Set `rollout.enabled: true` to render an **Argo Rollouts canary `Rollout`** instead
of the Deployment (the two are mutually exclusive). The Rollout:

- Splits traffic between a **stable Service** (`<fullname>`, 100% under steady
  state) and a **canary Service** (`<fullname>-canary`, the weighted fraction).
- Shifts traffic with the Gateway API plugin (`argoproj-labs/gatewayAPI`), which
  rewrites the `HTTPRoute` backendRef weights — Cilium drains connections on each
  shift. Requires `httpRoute.enabled: true`.
- Progresses through a weight ladder (default `10 → 30 → 50 → 100`) with an
  `AnalysisTemplate` gate between each step.
- Aborts gracefully via `abortScaleDownDelaySeconds`, keeping the canary
  ReplicaSet alive briefly so in-flight requests drain.

The container/pod definition is shared between Deployment and Rollout via the
`app.podSpec` helper, so the two kinds never diverge.

### Analysis gate (AnalysisTemplate)

When `rollout.analysis.enabled: true` (default), each canary step is gated on two
Prometheus metrics, scoped to the canary Service:

- **5xx error-rate** must stay `< 1%` (`rollout.analysis.errorRate`).
- **p95 latency** must stay `< 500ms` (`rollout.analysis.latencyP95`).

Disable it (`rollout.analysis.enabled: false`) for pure workers with no HTTP
metrics.

> **Where Kargo fits:** Kargo remains the planned promotion layer *above* this
> chart — it promotes verified artifacts between environments. This chart's
> `rollout` block governs the in-cluster canary once a version lands in an
> environment.

## Values

Key settings in `values.yaml`:

- `image.repository` – container image to deploy.
- `rollout.enabled` – switch from Deployment to an Argo Rollouts canary Rollout.
- `rollout.canary.weights` – progressive weight ladder for the canary.
- `rollout.analysis.enabled` – toggle the Prometheus metric gate between steps.
- `httpRoute.enabled` – enable the Gateway API HTTPRoute (required for canary traffic shifting).
- `ingress.enabled` – enable ingress.
- `ingress.className` – default ingress class.
- `ingress.extraClasses` – additional ingress classes to create separate ingress objects.
- `externalSecrets.enabled` – enable integration with External Secrets Operator.
- `externalSecrets.secretStoreRef` – reference to a `SecretStore` or `ClusterSecretStore` configured for AWS.

Consult the `values.yaml` file for the full list of configuration options.

## Provenance

The progressive-delivery machinery (`rollout.yaml`, `service-canary.yaml`,
`analysistemplate.yaml`, `httproute.yaml`, the `app.podSpec` shared helper, and
the `rollout` / `httpRoute` values blocks) was **ported from
`argocd@c364c6c` `charts/app`, 2026-06 sync**, adapted to this
chart's `app.*` helper templates and naming conventions.
