# ADR-0057: Separate platform-owned delivery observation from workload authority

- Status: **Proposed**
- Date: 2026-07-14
- Authors: platform-team
- Related issues: genai-enablement ADR-0013; 100rd/omnius ADR-0020 and SPEC-DO
- Supersedes: (none)
- Superseded by: (none)

## Context

`standard-http-service/v2` closes worker-authored inventory to six workload kinds and forbids
workload RBAC. Its observer must list runtime objects and forbidden inventory inside one preview
namespace. Kubernetes cannot restrict an ordinary `list` with `resourceNames`, so native
least-privilege observation requires one RoleBinding inside that namespace. Treating this binding as
workload inventory creates a contradiction; replacing it with cluster-wide read authority expands the
blast radius.

The access bundle also spans the Argo CD namespace and cluster-scoped Namespace identity. It must be
created by the platform control plane, independently attested, used with a short-lived credential, and
removed through registered compensation. Standard Kubernetes commonly grants discovery endpoints to
all authenticated principals, so a portable contract cannot falsely require `/api` and `/apis` denial.

## Decision

1. A delivery profile owns two disjoint signed sets: closed worker-authored workload inventory and
   closed platform control inventory.
2. `argocd-preview-http-service/v2` defines one shared versioned list-only ClusterRole and six exact
   WorkOrder objects: ServiceAccount, Application Role/RoleBinding, Namespace
   ClusterRole/ClusterRoleBinding, and preview Realm RoleBinding.
3. Platform rules contain no wildcard, mutation, secret/config, token, subresource, proxy, or
   `nonResourceURLs` authority. The observer transport has no discovery operation. An independent,
   signed attestor records complete effective authority, binds an adapter-owned authenticated
   cluster-baseline profile, and subtracts both that baseline and exact profile grants. The residual
   resource and non-resource rule sets must be empty. Inherited authority is evidence, not an
   implicit grant from this profile.
4. One issuer-signed observation scope binds an exact server, CA, audience, WorkOrder-derived
   identity, adapter configuration, ten-minute maximum token, thirty-second absolute deadline,
   one-MiB responses, and a 100-object Realm ceiling. Semantic verifiers and decision issuers must
   match adapter-owned profile digests and signing keys before recomputing these bindings.
5. Access compensation is registered before creation. Evidence is stored before normal revocation;
   terminal compensation and an independent reaper join against terminal-or-absent WorkOrder state
   and a signed positive `safeToReclaim` decision bound to terminal-or-absent WorkOrder state. Cleanup
   deletes only six exact WorkOrder objects with Kubernetes UID and resourceVersion preconditions,
   preserves
   the shared ClusterRole, and emits independently signed cleanup evidence.
6. The new `standard-service/v3` → `standard-http-service/v3` graph remains `draft` and is not admitted
   by `preview/v2`. This proposed decision and draft contract grant no execution authority.

## Alternatives considered

### Alternative A: ClusterRoleBinding for inventory list

Bind the shared list role cluster-wide and rely on client-side namespace checks.
Rejected because: a stolen token or transport defect could read every Realm.

### Alternative B: Ignore the observer RoleBinding

Exclude platform-labelled RBAC from Realm validation.
Rejected because: labels are forgeable workload data and do not prove exact roleRef, subject, rules,
provenance, or cleanup.

### Alternative C: Keep v2 unchanged and infer an exception

Let Omnius infer the required RBAC from Kubernetes behavior.
Rejected because: inferred authority is not an immutable platform contract and would silently change a
published path.

### Alternative D: Remove built-in discovery bindings

Harden each cluster until authenticated principals cannot reach discovery endpoints.
Rejected because: it is not portable, can break normal Kubernetes clients, and is unnecessary while
the closed transport exposes no discovery operation.

## Consequences

### Positive

- Worker authoring remains unable to add RBAC.
- Native observation is namespace-scoped without cluster-wide workload reads.
- Authority, state, inherited permissions, scope, and cleanup become signed, independently
  verifiable evidence bound to one WorkOrder and adapter configuration.
- Older v1/v2 bundles remain immutable.

### Negative

- Six WorkOrder objects plus one shared role add control-plane and cleanup load.
- The draft graph cannot execute until ADR acceptance, real-cluster qualification, and explicit Realm
  admission.

### Risks

- **A forged control object is mistaken for platform state.** Mitigation: exact identity, subject,
  roleRef, live rule digests, signed inventory digest, independent attestation, attestor profile, and
  signature key identity all must agree.
- **Access survives a failed workflow.** Mitigation: compensation is durable before mutation and an
  independent reaper requires the WorkOrder join and `safeToReclaim`; unavailable state alerts
  without deletion.
- **A same-name object is replaced during cleanup.** Mitigation: each delete revalidates and supplies
  the attested UID and resourceVersion as Kubernetes preconditions; conflict parks before deletion.
- **Evidence from another WorkOrder or time window is replayed.** Mitigation: signed scope, authority,
  snapshots, delivery evidence, and cleanup share exact identity digests, UIDs, temporal ordering,
  and schema-bound semantic verifiers.
- **Two passes are misrepresented as an atomic snapshot.** Mitigation: evidence calls them bounded
  stable observations and records each collection resourceVersion independently.

## Implementation notes

- Authority: `platform-contracts/delivery-profiles/argocd-preview-http-service/v2/` and the closed
  runtime schemas indexed with it.
- Candidate graph: `standard-service/v3`, `standard-http-service/v3`, `Environment/v3`, and
  `HttpService/v3`; no Realm admission is added.
- CI uses explicit format checking and semantic mutations to reject wildcard, worker ownership,
  cross-WorkOrder identity, overlong scope, false object counts, reused evidence digests, altered
  shared control objects, missing cleanup, and caller-controlled observer fields.
- Rollback removes the draft artifacts. Existing pinned v1/v2 bundles remain valid.

## References

- `platform-contracts/README.md`
- `genai-enablement/docs/decisions/0013-platform-owned-observer-access.md`
- `omnius/docs/adr/ADR-0020-platform-owned-delivery-observation.md`
- `omnius/specs/SPEC-DO-delivery-observation.md`
- ADR-0056
