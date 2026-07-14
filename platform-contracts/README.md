# Platform contracts

This directory is the machine-readable authority for platform products and executable
paths. Humans and agents consume the same schemas and instances. Omnius may execute only an
indexed bundle pinned by exact Git commit and bundle SHA-256.

## Layout

- `schemas/v1/` and later version directories define closed Draft 2020-12 schemas.
- `products/`, `entity-classes/`, `realms/`, `delivery-profiles/`, and `paths/` contain owned instances.
- `index.yaml` lists every authoritative file, its schema, and its content digest.
- `fixtures/` contains requests that must pass or fail validation.

The original `standard-service/v1` and `standard-http-service/v1` graph remains indexed and
unchanged. The delivery-bound first executable revision is `standard-service/v2` through
`standard-http-service/v2` in `preview/v2`. It accepts one authorized existing Go repository,
creates an internal HTTP service in a disposable `preview-<work-order-id>` Realm, and requires
human merge.

The proposed observer-access design is published as the separate draft
`standard-service/v3` → `standard-http-service/v3` graph with
`argocd-preview-http-service/v2`. It names `preview/v2` as a compatibility target but is not in that
Realm's admission list, so the bundle cannot authorize its execution. Acceptance, qualification, and
admission require later human-owned revisions.

## Publication and pinning

The bundle digest excludes `index.yaml` and is computed over the files in
`index.yaml.spec.artifacts`, sorted by path:

```text
sha256(path + NUL + file-bytes + path + NUL + file-bytes + ...)
```

Each artifact also has an individual SHA-256 in the index. A consumer must verify both and
record the exact 40-character Git commit. A branch, tag alone, working tree, copied catalog,
or Omniscience projection is not execution authority.

## Delivery profiles

A `PlatformDeliveryProfile` is the platform-owned bridge from an executable path to a concrete,
bounded delivery topology. It fixes trusted value sources, GitOps path and naming templates, logical
Argo CD and Kubernetes destination references, the allowed resource inventory, observation rules,
and compensation. Requests and agents cannot override those fields. Endpoint and credential lookup
for a logical reference remains adapter configuration governed outside the request.

The initial profile requires the repository-ownership policy to bind the authenticated WorkOrder
subject and declared owner to the exact repository before any repository-scoped credential is
issued. Its inventory kind set is closed, its only cluster-scoped object is one derived Namespace,
and compensation is bound to the same repository path, Application, namespace, inventory digest,
and ownership identity. Template variables bind explicitly to `workOrder.id`, the validated service
name, and the resolved Realm name. Missing authorization or scope evidence denies execution.

The profile does not grant apply authority to Omnius. For the initial path, a human merge lands the
change and Argo CD reconciles it; Omnius observes exact revision, health, image digest, Realm
containment, and eventual compensation through scoped read-only adapters.

Delivery profile v2 keeps the six workload kinds closed and adds a distinct platform-owned observer
control inventory. The worker cannot author it. Exact RBAC templates, signed short-lived scope,
independent signed authority and inherited-authority evidence, cleanup ordering, and guarded orphan
reaping are closed contract fields. Runtime schemas bind the resolved observation scope, per-kind
collection snapshots, delivery evidence, and cleanup evidence to the same WorkOrder-derived identity,
adapter configuration, object UIDs, and semantic verifiers. Each collection keeps its own
resourceVersion; the contract makes no cross-kind atomic-snapshot claim.

Kubernetes built-in bindings may grant `/api` and `/apis` discovery to authenticated principals. The
platform-owned rules grant no `nonResourceURLs`, the observer transport exposes no discovery method,
and a signed attestor records complete effective authority. It subtracts the exact profile grants and
an adapter-owned cluster baseline pinned by profile and rule digests; both residual rule sets must be
empty. This accommodates normal Kubernetes authenticated discovery without making it implicit. The exact
Secret/config, foreign-scope, subresource, token, watch, proxy, impersonation, `deletecollection`, and
other mutation denial matrix is evidence, including canonical request and response digests.

Attestor, scope issuer, delivery verifier, reclaim-decision issuer, and cleanup verifier profile
digests and signing keys come from adapter-owned trust anchors. Evidence cannot nominate its own
trusted signer.

Normal cleanup revokes the lease, revalidates and deletes only six exact WorkOrder-owned objects in
the specified order using attested UID and resourceVersion DELETE preconditions, verifies their
absence, and preserves the shared versioned inventory ClusterRole at its
attested digest. An orphan reaper may use the same plan only after a terminal-or-absent WorkOrder join
and signed positive `safeToReclaim` decision bound to that WorkOrder's terminal-or-absent state;
unavailable ownership state alerts without deletion.

`PlatformPath` schema v2 adds the required delivery-profile reference. The published v1 schema and
the complete v1 product/path/entity/Realm graph remain unchanged for consumers of older immutable
bundles; they are not silently given v2 semantics.

Run validation locally with:

```bash
python3 scripts/validate-platform-contracts.py
```

## Lifecycle

Artifacts move through `draft`, `experimental`, `validated`, `approved`, and `deprecated`.
The initial path is `experimental`: it is usable only where the indexed Realm explicitly
admits it, and it cannot be promoted without real delivery, probe, compensation, reliability,
and support evidence.
