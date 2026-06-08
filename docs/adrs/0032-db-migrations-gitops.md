# ADR-0032: DB migrations via ArgoCD PreSync Jobs

- Status: **Accepted** — doc-verified; ratified 2026-06-08 by platform owner.
- Date: 2026-06-08
- Authors: platform-team, delivery
- Related issues: #252
- Supersedes: (none) — the init-container migration pattern is deprecated by this ADR.
- Superseded by: (none)

## Context

The generic `helm/app` chart previously supported DB migrations through the
`initContainers` values block — teams could place a migration container there and it
would run before the main app container on every pod start. This approach has three
well-known failure modes that make it unsafe as the primary migration mechanism:

1. **Race condition across replicas.** When a `Deployment` scales up or rolls to a new
   version, Kubernetes starts multiple pods in parallel. Every pod runs its own init
   container simultaneously, so multiple migration processes compete to apply the same
   schema change. Most migration tools (`alembic`, `golang-migrate`, `flyway`, etc.)
   use a DB-level advisory lock to defend against this, but the race still causes
   contention, retries, and unpredictable start-up latency. A buggy or non-lock-aware
   migration tool can cause partial or duplicate migrations.

2. **No ordering guarantee relative to the rollout.** Init containers run inside the
   pod that is about to serve traffic. If the migration fails the pod crashes and the
   rollout stalls in `Pending` / `CrashLoopBackOff`. The old replica set is already
   being scaled down (rolling-update policy), so there is a window where *neither*
   version is fully available — both old pods that reached the drain point and new pods
   stuck crashing.

3. **Failure blocks individual pods, not the whole sync.** A migration error does not
   cleanly block a GitOps sync; it produces a partially-rolled-out deployment that must
   be diagnosed pod-by-pod. Rollback is manual and error-prone.

**ArgoCD resource hooks** (`argocd.argoproj.io/hook`) let us attach Kubernetes objects
to lifecycle events in a sync. A Job annotated `hook: PreSync` is created *before* any
other resource in the sync wave, must complete successfully before ArgoCD proceeds, and
is deleted automatically when it succeeds (`hook-delete-policy: HookSucceeded`). This
gives exactly the semantics DB migrations need: run once per sync, ordered strictly
before the workload rollout, with a clean success/failure signal that ArgoCD surfaces
on the Application object.

**Doc-verified 2026-06-08** against the official ArgoCD resource-hooks reference
(<https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/>) and sync-waves
reference (<https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/>):

- `argocd.argoproj.io/hook: PreSync` — the object is only created during a sync
  operation and runs to completion before any `Sync`-wave resources are applied.
- `argocd.argoproj.io/hook-delete-policy: HookSucceeded` — ArgoCD deletes the Job
  after it exits 0; if the Job fails the object is left in place for debugging, and the
  sync is marked `Failed` — the `Sync`-wave deployment never starts.
- `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation` (alternative policy) —
  deletes any previous instance of the Job before creating the new one; prevents
  name-collision on repeated syncs if the prior run was retained for debugging.
- Sync waves (`argocd.argoproj.io/sync-wave`) allow additional ordering within a phase;
  migration Jobs default to wave `-1` (earlier) within the PreSync phase to keep space
  for other PreSync hooks.

## Decision

Run DB migrations as **ArgoCD PreSync Jobs** rendered by the `helm/app` chart, gated
by `.Values.migrations.enabled`.

- The migration Job is annotated `argocd.argoproj.io/hook: PreSync` and
  `argocd.argoproj.io/hook-delete-policy: HookSucceeded`.
- It runs the same image as the main application (or an explicit override via
  `.Values.migrations.image`) with a configurable command
  (`.Values.migrations.command`).
- It inherits the application's `ServiceAccount`, `podSecurityContext`,
  `containerSecurityContext`, `envFrom` (DB credentials delivered via ESO,
  ADR-0008), and resource limits — a distinct `migrations.resources` override is
  provided for cases where migrations need more memory than the runtime container.
- The Job has `backoffLimit: 0` by default (no retries — a failed migration must not
  be silently retried with a broken half-applied schema) and
  `activeDeadlineSeconds: 300` (configurable) to bound the blast radius of a
  hung migration.
- The `initContainers` values block **remains in the chart** for non-migration use
  cases (e.g., wait-for-dependency sidecars) but **must not be used for schema
  migrations** by any application that opts into `migrations.enabled: true`.

A reviewer can confirm conformance by checking that no application combining
`migrations.enabled: true` with an init-container migration exists, that the migration
Job carries both hook annotations, that DB credentials flow exclusively from the ESO
secret (`envFrom`), and that `backoffLimit` is 0 (or explicitly justified otherwise).

## Alternatives considered

### Alternative A: Per-pod init-container migration (status quo)

Run the migration binary as an `initContainer` in the main Deployment/Rollout pod.
Rejected because: the three failure modes described in Context (race condition, no
global ordering, per-pod failure mode) make this approach unsafe at scale. It remains
supported for non-migration init use cases.

### Alternative B: Helm hook Job (`helm.sh/hook: pre-upgrade`)

The existing `helm/app` `jobs:` block already uses `helm.sh/hook: pre-install,pre-upgrade`.
Rejected as the *primary* migration mechanism because: Helm hooks are managed by Helm
(via the release secret); when ArgoCD manages the Application, the ArgoCD sync status
and the Helm hook execution are orthogonal. A failed Helm hook produces a failed Helm
release but ArgoCD may not surface this as a sync failure cleanly on all upgrade paths.
ArgoCD resource hooks integrate directly into the sync lifecycle and block the sync
reliably. The existing `jobs:` block is kept for non-migration Helm hooks.

### Alternative C: Kubernetes operator / migration controller (SchemaHero, Atlas)

Use a dedicated schema migration controller.
Rejected because: the platform does not yet have a migration operator deployed, and
introducing one is a larger cross-team dependency. The ArgoCD PreSync Job pattern
requires zero new operators, works with any migration binary, and is removable. A
dedicated operator may be re-evaluated in a future ADR once tooling is standardised
across teams.

### Alternative D: Do nothing / leave init-container pattern in place

Keep the current init-container approach.
Rejected because: the race-condition risk is real and has caused incidents in
production-like environments. The remediation cost of a partial migration is high.
PreSync Jobs eliminate the risk with minimal chart complexity.

## Consequences

### Positive

- Migration runs exactly once per sync, before any pod of the new version starts
  receiving traffic.
- A migration failure blocks the sync — ArgoCD marks the `Application` `Failed`, the
  existing workload pods continue to serve traffic uninterrupted, and no new pods of
  the bad version are started.
- Clean observability: ArgoCD UI shows the migration Job status; `kubectl logs` on the
  completed/failed Job give the full migration output.
- The migration Job is automatically cleaned up on success (`HookSucceeded`),
  preventing stale Job accumulation.
- No new operators required — works with any migration tool that exits 0 on success.

### Negative

- Teams must populate `migrations.command` correctly; a no-op command silently
  "succeeds" without migrating anything. Mitigated by chart documentation and a
  required non-empty validation note.
- The `backoffLimit: 0` default means a transient DB connectivity failure during the
  migration will fail the sync. Operators must re-sync after fixing connectivity.
  `backoffLimit` is explicitly configurable for teams that prefer retries.
- Long-running migrations block the entire sync, including unrelated resource changes.
  Teams should keep migrations fast or use online-safe migration patterns (additive
  changes, multi-step expand/contract).

### Risks

- **Risk:** A migration that is not idempotent runs twice (e.g., ArgoCD is forced to
  re-sync after a partial hook execution). Mitigation: use idempotent migration tools
  (`flyway`, `golang-migrate`, `alembic`) that track applied versions in a
  `schema_migrations` table — running them twice is safe.
- **Risk:** DB credentials not present in the ESO secret at sync time cause the
  migration Job to fail with a `CreateContainerConfigError`. Mitigation: ESO is in a
  `PreSync` wave before the migration Job (via sync-wave ordering); chart documentation
  requires `externalSecrets.enabled: true` when `migrations.enabled: true`.
- **Risk:** A migration that is destructive (drop column) runs against the wrong
  environment. Mitigation: standard GitOps controls — the migration image/command is
  in Git, changes go through PR review, and environments use distinct ArgoCD
  Applications pointing at distinct value files.

## Implementation notes

- Files / modules touched:
  - `helm/app/templates/migration-job.yaml` (new) — the PreSync Job template.
  - `helm/app/values.yaml` — new `migrations:` block appended.
  - `helm/app/README.md` — PreSync pattern documented.
- Rollback procedure: set `migrations.enabled: false` to suppress the Job. If a
  migration has already been applied and must be reverted, run the rollback manually
  (`helm/app` provides no automatic rollback of applied schema changes — use the
  migration tool's own down-migration capability).
- CI/test: `helm lint helm/app` and `helm template helm/app` (with
  `migrations.enabled=true` and `=false`) validate rendering; YAML safe-load confirms
  valid YAML; the `PreSync` annotation is verified in CI output.

Effort: **S**.

## References

- ArgoCD resource hooks: <https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/>
- ArgoCD sync waves: <https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/>
- ArgoCD hook delete policies: <https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/#hook-deletion-policies>
- Related: ADR-0006 (ArgoCD for GitOps), ADR-0008 (External Secrets Operator), ADR-0014 (Argo Rollouts canary)

---
*Doc-verified 2026-06-08 (ArgoCD official resource-hooks + sync-waves docs) — 2026
platform modernization; grounded in argocd@c364c6c. Accepted, ratified 2026-06-08 by
platform owner.*
