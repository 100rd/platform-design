# standard-http-service/v3

This draft path would change one existing Go 1.23 HTTP service and prove it in a
disposable preview Realm. It is an execution contract, not a claim that the current estate
already implements every registered action or probe.

## Request boundary

The request names one existing GitHub repository and a safe relative source subpath. Runtime,
exposure, port, and resource size are fixed. Acceptance probes are bounded origin-form `GET`
requests with HTTP 200, a fixed media type, and either exact text or a shallow JSON subset. Paths
cannot contain an authority, empty/repeated segment, dot segment, percent encoding, query, fragment,
or backslash. Unknown fields and duplicate paths fail validation.

The request cannot supply commands, scripts, environment variables, secrets, image tags, Helm
values, policy overrides, namespaces, clusters, accounts, or production targets. Identity and
the effective `preview-<work-order-id>` Realm are derived by trusted intake and policy code.

The path binds `argocd-preview-http-service/v2` as its platform-owned delivery profile. That
profile, rather than caller or agent input, fixes the GitOps path template, Argo CD control-plane
and project references, target cluster reference, Application and namespace names, resource
envelope, observation rules, and compensation. Logical control-plane and cluster references are
resolved only through separately governed adapter configuration; they are not network endpoints or
credentials supplied by a request. The desired inventory digest comes from the deterministic
source-validation step, not from the authoring worker.

The request repository is not authority by itself. Execution requires
`source.repository-owner-authorized/v1` to bind the authenticated WorkOrder subject, owner, exact
repository, and exact-repository credential scope. Compensation reuses the same repository,
work-order-specific GitOps path, Application, derived namespace, inventory digest, and ownership
identity; none of those targets can be replaced by compensation input.

The workload desired inventory remains the same closed six-kind set as v2. Observer access is a
separate platform control inventory: one shared versioned list-only ClusterRole and six exact
WorkOrder objects. Workers cannot author those objects. The control plane registers cleanup before
creation, obtains signed independent live-RBAC evidence, issues an issuer-signed WorkOrder and
adapter-bound short-lived scope, and stores schema-bound observation evidence. It then issues a
separate five-minute runtime credential to the same WorkOrder-specific read-only identity. That
identity can additionally list EndpointSlices; it remains unable to read Secrets or ConfigMaps,
watch, proxy, execute, mint tokens, or mutate anything. The access bundle is removed immediately
after runtime verification and is also covered by terminal compensation.

The observer transport has no discovery operation and platform-owned rules contain no
`nonResourceURLs`. Kubernetes may still grant `/api` and `/apis` through its built-in
`system:discovery` binding; that inherited authority is recorded separately and is never accepted as
observation input. A complete effective-authority report subtracts an adapter-pinned authenticated
cluster baseline and the exact profile grants; both residual rule sets must be empty. The report and
exact negative-authorization matrix are signed by an attestor outside the observer identity.
Forbidden resource, subresource, foreign-scope, and mutation checks remain fail-closed.

## Condition of Done

Before execution, Omnius binds the exact request, path commit, bundle digest, policies,
actions, probes, expected responses, compensation, and evidence TTL. Completion requires:

1. The source diff stays inside the bound repository and source/GitOps paths.
2. Unit, build, and security checks pass on the exact commit.
3. The image is built once; SBOM and signature evidence bind its immutable digest.
4. A Draft PR is opened idempotently and a human merges it.
5. Argo CD reports `Synced` and `Healthy` for the exact Git and image revisions.
6. Independent authority evidence binds the exact platform control inventory, negative checks,
   inherited authority, credential scope, transport recording, and live RBAC digests.
7. Two complete bounded inventory passes prove stable exact-revision delivery and Realm containment.
8. A fresh signed HTTP subject binds the frozen acceptance digest, exact bundle/profile, WorkOrder,
   cluster, Namespace/Service identity, delivery evidence, merge commit, image digest, and deadline.
9. A dedicated quota-bound, default-deny preview namespace has no production credentials,
   shared-state access, data mutation, or cross-Realm authority.
10. `/healthz`, `/readyz`, and every requested route pass three consecutive all-backend batches.
    Every batch directly probes the complete one-through-three ready Pod set in deterministic order;
    pre/post Service, EndpointSlice, Pod UID/address, readiness, and image snapshots must match.
11. Observer access is revoked through attested UID and resourceVersion DELETE preconditions; signed
    cleanup evidence proves six exact WorkOrder objects absent, the credential lease revoked, and the
    shared versioned ClusterRole preserved after runtime verification.
12. The evidence manifest is immutable and no older than `PT24H`.
13. Registered compensation can close an unmerged PR or revert the landed change, revoke observer
   access, and prune the preview Realm; the verifier proves absence of WorkOrder-owned resources.

Any missing, expired, conflicting, or unverifiable result prevents verified completion.

The effect-local `delivery.close-unmerged-draft-pull-request/v1` compensator covers only the
open-PR side effect before human merge. The path-level
`delivery.revert-prune-and-revoke-preview/v2` action remains a separate composite Saga for a landed
change, observer access, and preview resources; closing a Draft PR cannot satisfy the path-level
verifier.

## Current admission

The draft path names `preview/v2` only as its candidate compatibility boundary; no Realm admits it.
Accepting the governing ADR, qualifying the real access/cleanup path, and publishing an admitted
revision are separate human decisions. Omnius cannot execute this draft or widen admission from task
input or its own outcome feedback.
