# Generic Application Chart

This Helm chart deploys a generic application container with optional Nginx ingress and integration with the External Secrets Operator using AWS as the backend.

## Features

- Deployment **or** Argo Rollouts canary (`rollout.enabled` toggle) — mutually exclusive workload kinds sharing one pod spec.
- Service resource, plus an optional weighted **canary Service** for progressive delivery.
- Optional Ingress resource supporting multiple ingress classes (e.g., `nginx`, `internal-nginx`).
- Optional Gateway API `HTTPRoute` for internal ingress and canary traffic shifting.
- Optional ExternalSecret resource to fetch secrets from AWS Secrets Manager via External Secrets Operator.
- **ArgoCD PreSync DB migration Job** (`migrations.enabled` toggle) — runs schema migrations before the workload rollout on every sync, replacing the unsafe per-pod init-container migration pattern.

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

## DB Migrations via ArgoCD PreSync Jobs (ADR-0032)

### Why PreSync Jobs instead of init containers

The previous pattern for DB migrations was to place the migration binary in an
`initContainers` entry. This approach has three unsafe failure modes:

1. **Race condition.** All pods of a rolling update start simultaneously and every
   pod runs its own init container. Multiple migration processes compete against the
   same schema, causing contention and — for non-lock-aware tools — partial or
   duplicate migrations.

2. **No global ordering.** Init containers run inside each pod, not before the rollout
   begins. A failed migration crashes the pod, stalling the rollout in
   `CrashLoopBackOff` while the old replica set is already being scaled down.

3. **No clean sync-failure signal.** A migration failure does not block an ArgoCD
   sync cleanly; it produces a partially-rolled-out deployment that must be diagnosed
   pod-by-pod.

ArgoCD **resource hooks** solve all three. A Job annotated
`argocd.argoproj.io/hook: PreSync`:

- Is created **once per sync**, before any Sync-phase resource (Deployment, Service,
  ConfigMap, etc.).
- Must **exit 0** before ArgoCD proceeds to the Sync phase. On failure ArgoCD marks
  the Application `Failed` and the rollout never starts — existing pods keep serving
  traffic.
- Is **deleted automatically** after success (`hook-delete-policy: HookSucceeded`).
- Handles name-collision cleanup on re-sync (`hook-delete-policy: BeforeHookCreation`).

This means migrations run exactly once per sync, in a defined order, with a clean
pass/fail signal visible in the ArgoCD UI and `kubectl get jobs`.

### Enabling migrations

```yaml
# values-production.yaml
image:
  repository: ghcr.io/myorg/myapp
  tag: "1.5.2"

externalSecrets:
  enabled: true
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: /prod/myapp/db
        property: url

migrations:
  enabled: true
  command: ["migrate", "-path", "/migrations", "-database", "$(DATABASE_URL)", "up"]
  # image: ""           # empty = reuse main app image (common case)
  # backoffLimit: 0     # no retries (safe default for non-idempotent tools)
  # activeDeadlineSeconds: 300   # 5-minute wall-clock timeout
```

Apply with ArgoCD:

```
argocd app sync myapp
```

ArgoCD will:
1. Create the `<release>-app-migrate` Job (PreSync, wave -1).
2. Wait for the Job to exit 0.
3. Apply the Deployment/Rollout, Service, and other Sync-phase resources.
4. Delete the migration Job (HookSucceeded).

### Rollback

To skip the migration Job on the next sync (e.g., emergency rollback of the app
image without re-running migrations):

```yaml
migrations:
  enabled: false
```

**Schema rollback is not automatic.** If a migration applied destructive changes
(dropped a column, renamed a table), use the migration tool's own down-migration
capability. `helm/app` does not provide schema rollback automation.

For online-safe migration strategies, prefer additive changes and the
expand/contract pattern: add the new column, deploy the code that handles both,
then drop the old column in a subsequent sync.

### Migration image override

By default the migration container reuses the main application image. Override
`migrations.image` when the migration binary is shipped separately:

```yaml
migrations:
  enabled: true
  image: "ghcr.io/myorg/myapp-migrations:1.5.2"
  command: ["alembic", "upgrade", "head"]
```

### Resource limits for migrations

Migrations that perform ORM introspection or large schema diffs may need more
memory than the runtime pod. Set `migrations.resources` to override:

```yaml
migrations:
  enabled: true
  command: ["flyway", "migrate"]
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

When `migrations.resources` is empty (`{}`), the main app `resources` block is
used (the default).

### Relationship to initContainers

The `initContainers` values block **remains available** for non-migration use
cases (e.g., waiting for a dependency to become healthy, rendering config files).
Do not use `initContainers` for schema migrations when `migrations.enabled: true`
— the PreSync Job is the authoritative migration mechanism per ADR-0032.

## Values

Key settings in `values.yaml`:

- `image.repository` — container image to deploy.
- `rollout.enabled` — switch from Deployment to an Argo Rollouts canary Rollout.
- `rollout.canary.weights` — progressive weight ladder for the canary.
- `rollout.analysis.enabled` — toggle the Prometheus metric gate between steps.
- `httpRoute.enabled` — enable the Gateway API HTTPRoute (required for canary traffic shifting).
- `ingress.enabled` — enable ingress.
- `ingress.className` — default ingress class.
- `ingress.extraClasses` — additional ingress classes to create separate ingress objects.
- `externalSecrets.enabled` — enable integration with External Secrets Operator.
- `externalSecrets.secretStoreRef` — reference to a `SecretStore` or `ClusterSecretStore` configured for AWS.
- `migrations.enabled` — render the ArgoCD PreSync migration Job.
- `migrations.command` — migration entrypoint (required when `migrations.enabled: true`).
- `migrations.image` — override image for the migration container (default: reuse app image).
- `migrations.activeDeadlineSeconds` — wall-clock timeout for the migration Job (default: 300).
- `migrations.backoffLimit` — retry count on failure (default: 0).
- `migrations.resources` — resource requests/limits for the migration container (default: inherit from `resources`).

Consult the `values.yaml` file for the full list of configuration options.

## Provenance

The progressive-delivery machinery (`rollout.yaml`, `service-canary.yaml`,
`analysistemplate.yaml`, `httproute.yaml`, the `app.podSpec` shared helper, and
the `rollout` / `httpRoute` values blocks) was **ported from
`argocd@c364c6c` `charts/app`, 2026-06 sync**, adapted to this
chart's `app.*` helper templates and naming conventions.

The DB migration machinery (`migration-job.yaml`, `migrations` values block) was
**added 2026-06-08** per **ADR-0032**, replacing the unsafe per-pod init-container
migration pattern with an ArgoCD PreSync Job.
