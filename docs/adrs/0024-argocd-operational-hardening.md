# ADR-0024: ArgoCD operational hardening (PreDelete hooks, shallow clone, server-side diff/apply, progressive ApplicationSet rollout)

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — shallow clone + server-side diff/apply + RollingSync + PreDelete (#259).
- Date: 2026-06-07
- Authors: platform-team
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Extends: ADR-0006 (ArgoCD for GitOps), ADR-0012 (`cluster_role` ApplicationSet labels).

## Context

ArgoCD (ADR-0006) is the GitOps engine across the clusters×git matrix. The estate
runs **ArgoCD 3.3.6 (chart 9.5.1)** — a version that already ships four operational
capabilities we are **not yet using**, and that need **no upgrade** to enable:

1. **Deletion ordering** is uncontrolled — when a resource is removed, ArgoCD just
   deletes it; there is no hook to drain/deregister first.
2. **Full git clones** on every reconcile cost repo-server memory and wall-clock on
   large repos.
3. **Client-side diffing** produces **spurious `OutOfSync`** across the
   clusters×git matrix when webhook/defaulting/mutation rewrites fields — noisy and
   sync-churn-inducing.
4. **ApplicationSet rollouts are all-at-once** — a bad generated Application can
   land on every cluster simultaneously, with no staged dev→stage→prod gating.

All four are configuration on the version already running.

## Decision

Enable the four ArgoCD 3.3.6 capabilities now (no version bump):

- **PreDelete sync hooks** — run a **Job before resource deletion** (drain
  connections, deregister from a load balancer / service registry) so teardown is
  ordered, not abrupt.
- **Shallow git clone** — fetch only the **required commit(s)** rather than full
  history → **faster reconcile** and **less repo-server memory** on large repos.
- **Server-Side Diff / Server-Side Apply** — diff via the API server
  (**webhook/defaulting-aware**), which **eliminates spurious `OutOfSync`** caused
  by server-side field mutation across the clusters×git matrix.
- **ApplicationSet Progressive / RollingSync** — staged rollout of generated
  Applications **dev → stage → prod**, sequenced by the **`cluster_role` labels**
  (ADR-0012), so a change soaks in lower environments before prod.

A reviewer can check conformance by confirming PreDelete hooks exist on
teardown-sensitive resources, repo-server uses shallow clone, server-side diff/apply
is enabled (no spurious `OutOfSync`), and ApplicationSets use
Progressive/RollingSync keyed on the `cluster_role` labels.

## Alternatives considered

### Alternative A: Status quo — leave the four capabilities off
Keep client-side diff, full clones, unordered deletes, all-at-once ApplicationSet
rollout.
Rejected because: spurious `OutOfSync` is operational noise across the whole matrix,
full clones waste repo-server memory, unordered deletes risk dropping live traffic,
and all-at-once rollout removes the dev→prod safety gradient — all fixable on the
running version for free.

### Alternative B: Upgrade ArgoCD first to get these features
Defer until a major upgrade.
Rejected because: **3.3.6 already ships all four** — there is nothing to upgrade
for. Enabling them now is independent of any future bump.

### Alternative C: Solve diff noise with per-resource `ignoreDifferences` instead of server-side diff
Patch around spurious diffs with hand-maintained ignore rules.
Rejected because: `ignoreDifferences` is a growing per-field maintenance burden that
masks real drift; server-side diff fixes the root cause (server-side field
mutation) globally.

## Consequences

### Positive
- Ordered teardown (PreDelete drain/deregister) — no abrupt deletion of live
  resources.
- Lower repo-server memory + faster reconcile via shallow clone.
- **Spurious `OutOfSync` eliminated** matrix-wide via server-side diff/apply.
- Staged dev→stage→prod ApplicationSet rollout — a bad change soaks before prod.

### Negative
- Four behaviours to configure and validate; server-side apply changes
  field-ownership semantics teams must understand.

### Risks
- A PreDelete hook that hangs blocks deletion. Mitigated by hook timeouts +
  `hook-delete-policy`.
- Server-side apply field-ownership conflicts with a controller that also writes the
  field. Mitigated by rolling it out per-app and watching for apply conflicts.
- RollingSync mis-labeled cluster_role stalls a rollout. Mitigated by validating the
  ADR-0012 labels before enabling progressive sync.

## Implementation notes

- Files / modules touched: ArgoCD chart values (shallow clone, server-side
  diff/apply), Application/ApplicationSet specs (PreDelete hooks, RollingSync
  strategy keyed on `cluster_role`).
- Migration: enable shallow clone + server-side diff first (lowest risk), then
  PreDelete hooks on teardown-sensitive apps, then RollingSync on ApplicationSets.
- Rollback: each is an independent values/spec flag — revert individually.
- CI/test: manifest-validate (ADR-0016) covers the ApplicationSet/Application
  changes.

Effort: **L**.

## References

- ArgoCD sync phases & hooks (PreSync/Sync/PostSync/PreDelete):
  <https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/>
- ArgoCD server-side diff / server-side apply:
  <https://argo-cd.readthedocs.io/en/stable/user-guide/diff-strategies/>
- ApplicationSet Progressive Syncs (RollingSync):
  <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Progressive-Syncs/>
- Related: ADR-0006 (ArgoCD for GitOps), ADR-0012 (`cluster_role` ApplicationSet labels)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
