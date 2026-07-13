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
