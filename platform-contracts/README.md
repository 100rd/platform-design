# Platform contracts

This directory is the machine-readable authority for platform products and executable
paths. Humans and agents consume the same schemas and instances. Omnius may execute only an
indexed bundle pinned by exact Git commit and bundle SHA-256.

## Layout

- `schemas/v1/` defines closed Draft 2020-12 schemas.
- `products/`, `entity-classes/`, `realms/`, and `paths/` contain owned instances.
- `index.yaml` lists every authoritative file, its schema, and its content digest.
- `fixtures/` contains requests that must pass or fail validation.

The first vertical is `standard-service/v1` through
`standard-http-service/v1`. It accepts one existing Go repository, creates an internal HTTP
service in a disposable `preview-<work-order-id>` Realm, and requires human merge.

## Publication and pinning

The bundle digest excludes `index.yaml` and is computed over the files in
`index.yaml.spec.artifacts`, sorted by path:

```text
sha256(path + NUL + file-bytes + path + NUL + file-bytes + ...)
```

Each artifact also has an individual SHA-256 in the index. A consumer must verify both and
record the exact 40-character Git commit. A branch, tag alone, working tree, copied catalog,
or Omniscience projection is not execution authority.

Run validation locally with:

```bash
python3 scripts/validate-platform-contracts.py
```

## Lifecycle

Artifacts move through `draft`, `experimental`, `validated`, `approved`, and `deprecated`.
The initial path is `experimental`: it is usable only where the indexed Realm explicitly
admits it, and it cannot be promoted without real delivery, probe, compensation, reliability,
and support evidence.
