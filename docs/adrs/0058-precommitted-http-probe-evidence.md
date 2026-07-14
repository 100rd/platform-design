# ADR-0058: Precommit HTTP completion and verify every delivered backend

- Status: **Proposed**
- Date: 2026-07-14
- Authors: platform-team
- Related issues: genai-enablement ADR-0014; 100rd/omnius draft HTTP verifier work
- Supersedes: (none)
- Superseded by: (none)

## Context

The draft `standard-http-service/v3` path names health, readiness, and request-contract Conditions of
Done but only registers symbolic probe and evidence identifiers. It does not yet define the frozen
probe semantics, target attribution, four-state reduction, signed result shape, or replay boundary.
Implementing a network client against those symbols would let the executor choose its own oracle and
would not prove that responses came from the delivered image.

## Decision

1. The platform publishes one closed `http-preview-service/v1` probe profile. It fixes origin-form
   `GET` paths, status/body comparison, one-through-three ready backends, attempt limits, deadlines,
   response bounds, four result states, aggregation, canonicalization, and external verifier trust.
2. Request acceptance is frozen before mutation in the execution envelope. After independently
   verified delivery, a closed run subject binds that envelope and acceptance digest to WorkOrder,
   cluster, Realm, Namespace, Service routing spec, merge commit, image digest, fresh delivery
   evidence, and the exact profile revision.
3. The verifier derives the complete EndpointSlice backend set. Every endpoint must identify an
   admitted Pod UID running the frozen image digest. Each attempt directly probes every backend in
   deterministic stable backend order and records pre/post Service and backend snapshots. Empty, excess,
   external, unready, mixed-image, changed, or recreated targets are `probe-error`.
4. Caller input is limited to a strict ASCII origin path: exactly one leading slash, non-empty
   unreserved segments, and no repeated slash, dot segment, percent encoding, backslash, query,
   fragment, authority, header, credential, proxy, redirect, or alternate method.
5. Backend, batch, and condition results use exactly `pass`, `fail`, `inconclusive`, or
   `probe-error`. A batch passes only when all unchanged backends pass. Three consecutive passing
   batches are required; every non-pass resets the streak and remains in evidence.
6. Signed evidence binds unique run/attempt identity and order, subject and delivery digests,
   pre/post target snapshots, per-backend status/content digests, bounded oracle projections,
   aggregate results, time, expiry, verifier profile, and signing key. Duplicate, stale, reordered,
   cross-cluster, cross-run, or worker-signed evidence cannot satisfy a condition.
7. The probe profile is attached only to draft delivery profile
   `argocd-preview-http-service/v2`. This candidate revision remains outside Realm admission and
   readiness. Existing v1/v2 executable bundles are unchanged.

## Alternatives considered

### Accept one caller-supplied URL

Rejected because URL resolution, redirects, proxy inheritance, and credentials create SSRF and
cross-Realm authority channels.

### Probe only the logical Service

Rejected because a Service UID can retain a changed selector and one load-balanced response does not
attribute success to every ready backend or the frozen image digest.

### Store complete response bodies

Rejected because bounded canonical projections and digests are sufficient to audit deterministic
comparisons without retaining arbitrary application data.

## Consequences

### Positive

- Conditions are fixed before implementation and checked by an external oracle.
- Runtime success is tied to every stable delivered backend, not a worker assertion.
- Failure, insufficient evidence, and verifier failure remain distinct and fail closed.

### Negative

- Runtime verification requires fresh Kubernetes reads and direct Realm-network reachability.
- A rollout or backend restart during the short run invalidates the run and requires a retry.
- The preview profile intentionally excludes TLS, authentication, write methods, streaming, deep
  JSON, SLO claims, and production use.

## Implementation notes

- Authority: indexed profile plus closed subject/result schemas under `platform-contracts/`.
- Validation: positive examples and semantic mutations cover target drift, empty backend sets,
  mixed results, duplicate attempts, stale delivery, cross-run replay, path injection, and untrusted
  verifier identity.
- Omnius must first implement transport-neutral comparison and evidence verification. Network
  transport qualification is a separate step and cannot create Realm admission by itself.

## References

- `genai-enablement/docs/decisions/0014-precommitted-http-condition-evidence.md`
- `platform-contracts/paths/standard-http-service/v3/`
- ADR-0056
- ADR-0057
