# ADR-0012: `cluster_role` label scheme for ArgoCD ApplicationSet selectors

- Status: **Accepted** — decision is *adopted (live in source estate)*
- platform-design status: **synced** — ApplicationSets select on a
  `cluster-role` label (`argocd/bootstrap/applicationsets/role-apps-appset.yaml`
  matchExpression + `apps/cluster-roles/{{cluster-role}}/*`; infra /
  observability appsets and overlay kustomizations set the label). Concrete
  role values here are `dex` / `backend` / `3rd-party` / `velocity` /
  `listeners` rather than the ADR's illustrative `platform`/`app`/`data`, but
  the label-driven selector scheme is the live decision.
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

ArgoCD ApplicationSets (ADR-0006) use a cluster-selector matrix to decide which
clusters receive which Applications. The selector filters on labels of the ArgoCD
cluster secret, which are populated by the `modules/argocd-bootstrap` module via
its `cluster_labels` input.

The GitOps repo's ApplicationSet manifests target the platform/shared cluster
with `cluster_role: "platform"`. The bootstrap module originally labelled the
shared cluster secret `cluster_role: "shared"`. The mismatch caused AppSets to
produce **zero** Applications for the shared cluster — workloads never deployed.

Two fixes were possible: change the AppSet selectors in the GitOps repo, or
change the cluster label in the infra repo.

## Decision

Set `cluster_labels.cluster_role = "platform"` (not `"shared"`) in the shared
cluster's `argocd-bootstrap` unit. The `cluster_role` label is a **cluster
identity claim** (`platform` / `app` / `data`), distinct from the account name,
which is conveyed by a separate `env` label (`env = "shared"`).

A reviewer can check conformance by confirming the cluster-role label value
matches the AppSet selector convention (`platform`), and that `env` carries the
account name separately.

## Alternatives considered

### Alternative A: Change AppSet selectors from `platform` to `shared`
Update the GitOps repo's ApplicationSets instead.
Rejected because: the AppSet selector is the consumed contract across multiple
teams; `platform` is the established convention. Changing it requires coordinated
updates to every AppSet and inverts the established label semantics.

### Alternative B: Add a second label rather than changing `cluster_role`
Leave `cluster_role = "shared"` and add `cluster_role_alias = "platform"`.
Rejected because: it leaves two competing identity labels and invites future
drift; the selector contract should resolve to one canonical value.

### Alternative C: Status quo
Leave the mismatch.
Rejected because: it means zero Applications deploy to the shared cluster — the
bug this ADR fixes.

## Consequences

### Positive
- AppSets filtering on `cluster_role: "platform"` deploy to the shared cluster.
- Minimal blast radius: one Helm value in one Terragrunt unit; the cluster secret
  is updated in place on next apply, no Application resources destroyed.
- `env = "shared"` retained for account-level filtering by other AppSets.

### Negative
- The intentional mismatch between account name ("shared") and cluster-role label
  ("platform") must be documented (here) so nobody "fixes" it back.

### Risks
- After apply, verify AppSet dry-run output to ensure no unintended Applications
  are triggered by the now-matching selector.
- Future "platform"-role clusters must also use `cluster_role = "platform"` to be
  included in the same AppSet matrix row.

## Implementation notes

- `shared/eu-west-1/argocd-bootstrap/terragrunt.hcl`: `cluster_labels.cluster_role
  = "platform"`, `env = "shared"`.
- Do **not** revert `cluster_role` to `"shared"`.

## References

- ArgoCD ApplicationSet cluster generator: <https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/>
- Ported from `infra` ADR-011 (cluster_role label scheme) and the
  `argocd` ApplicationSet selectors
- Related: ADR-0006 (ArgoCD GitOps)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
