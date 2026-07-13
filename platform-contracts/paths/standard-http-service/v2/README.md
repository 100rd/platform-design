# standard-http-service/v2

This experimental path changes one existing Go 1.23 HTTP service and proves it in a
disposable preview Realm. It is an execution contract, not a claim that the current estate
already implements every registered action or probe.

## Request boundary

The request names one existing GitHub repository and a safe relative source subpath. Runtime,
exposure, port, and resource size are fixed. Acceptance probes are bounded `GET` requests with
HTTP 200 and either exact text or a shallow JSON subset. Unknown fields fail validation.

The request cannot supply commands, scripts, environment variables, secrets, image tags, Helm
values, policy overrides, namespaces, clusters, accounts, or production targets. Identity and
the effective `preview-<work-order-id>` Realm are derived by trusted intake and policy code.

The path binds `argocd-preview-http-service/v1` as its platform-owned delivery profile. That
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

## Condition of Done

Before execution, Omnius binds the exact request, path commit, bundle digest, policies,
actions, probes, expected responses, compensation, and evidence TTL. Completion requires:

1. The source diff stays inside the bound repository and source/GitOps paths.
2. Unit, build, and security checks pass on the exact commit.
3. The image is built once; SBOM and signature evidence bind its immutable digest.
4. A Draft PR is opened idempotently and a human merges it.
5. Argo CD reports `Synced` and `Healthy` for the exact Git and image revisions.
6. A dedicated quota-bound, default-deny preview namespace has no production credentials,
   shared-state access, data mutation, or cross-Realm authority.
7. `/healthz`, `/readyz`, and every requested route pass three consecutive bounded probes
   from a verifier outside the worker identity and writable environment.
8. The evidence manifest is immutable and no older than `PT24H`.
9. Registered compensation can close an unmerged PR or revert the landed change and prune the
   preview Realm; the prune verifier proves absence of owned resources.

Any missing, expired, conflicting, or unverifiable result prevents verified completion.

The effect-local `delivery.close-unmerged-draft-pull-request/v1` compensator covers only the
open-PR side effect before human merge. The path-level
`delivery.revert-and-prune-preview/v1` action remains a separate composite Saga for a landed
change and its preview resources; closing a Draft PR cannot satisfy the path-level verifier.

## Current admission

Only `preview/v2` admits this experimental path. Human merge remains mandatory. Promotion to
another Realm requires a new reviewed contract revision and lower-Realm evidence; Omnius cannot
widen admission from task input or its own outcome feedback.
