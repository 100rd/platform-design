# ADR-0059: Separate observer authority attestation by trust class

- Status: **Proposed**
- Date: 2026-07-14
- Authors: platform-team
- Related issues: genai-enablement ADR-0015; 100rd/omnius observer attestation verifier
- Supersedes: (none)
- Superseded by: (none)

## Context

ADR-0057 requires an independent signature over the effective authority of each short-lived
delivery observer, but the draft contract does not identify who may produce that evidence or how a
verifier distinguishes disposable local qualification from production evidence. Leaving the
attestor identity, signing root, cluster binding, expiry, or signature payload to an adapter would
permit self-attestation, cross-cluster replay, and accidental admission of development evidence.

## Decision

1. The platform publishes two closed, versioned, draft attestor profiles:
   `kind-development/v1` for local qualification and `eks-kms-ed25519/v1` for the production design.
   Both have `readinessEligible: false` until the human-owned cross-repo decision is accepted and a
   separate readiness profile admits an exact implementation revision.
2. Production uses the dedicated
   `system:serviceaccount:darkfactory-attestors:observer-rbac-attestor` identity on the
   platform-control node boundary. It is separate from the observer, worker, delivery verifier,
   cleanup/reaper, and planner identities.
3. The attestor may read only the bounded identity and RBAC object kinds needed to resolve observer
   authority and may create SubjectAccessReview requests. It receives no observer credential,
   impersonation, Secret/ConfigMap read, TokenRequest, workload or RBAC mutation, or cleanup
   authority. WorkOrder facts come from the signed execution envelope, not a cluster-authored task.
4. The production profile uses EKS Pod Identity and one pinned asymmetric AWS KMS
   `ECC_NIST_EDWARDS25519` key with `ED25519_SHA_512`. The private key is never stored in Kubernetes.
   The local profile uses a per-run process-memory Ed25519 key outside the observer identity and is
   non-admissible by construction.
5. Evidence binds the exact signed execution-envelope digest, platform commit and bundle, delivery
   profile, attestor profile, cluster identity, live access-object epochs, every required-positive and
   forbidden-negative SubjectAccessReview decision, WorkOrder identity, and a maximum five-minute
   validity window.
6. The canonical evidence digest excludes `evidenceSha256` and `signature.value`. The signature is
   Ed25519 over the domain-separated payload
   `UTF8("darkfactory.observer-access-attestation/v1") || 0x00 ||
   hex_to_bytes(evidenceSha256)`.
7. Publishing these draft contracts does not admit `standard-http-service/v3`, create production
   cloud resources, or grant autonomous execution readiness.

## Alternatives considered

### Let the observer sign its own authority

Rejected because compromise of the observer token would also compromise the admission oracle.

### Use an administrative kubeconfig as the production attestor

Rejected because it has an unbounded authority surface and lacks workload-identity provenance.

### Use one profile for kind and EKS

Rejected because a disposable local key and loopback cluster identity must never be replayable as
production readiness evidence.

### Store the production signing key in a Kubernetes Secret

Rejected because cluster Secret readers could forge the external authority proof.

## Consequences

### Positive

- Attestor identity, authority, signer, payload, freshness, and cluster binding are machine-checkable.
- Development qualification can exercise the full verifier without acquiring production authority.
- Unknown profiles, extra authority, stale evidence, and cross-cluster replay fail closed.

### Negative

- The production design depends on EKS Pod Identity, AWS KMS, and a protected platform-control node
  boundary.
- SubjectAccessReview alone is insufficient; the attestor must also resolve and freeze all applicable
  RBAC objects and inherited authority.
- Real-cluster qualification and independent cleanup/reaper evidence remain readiness blockers.

## Implementation notes

- Profiles live under `platform-contracts/attestor-profiles/` and are indexed in the platform bundle.
- `argocd-preview-http-service/v2` catalogs both profiles but keeps its readiness profile list empty.
- Semantic validation rejects profile mutation, self-granted readiness, a Kubernetes-held private
  key, cluster-owned WorkOrder authority, signer substitution, bundle/cluster replay, and overlong
  evidence lifetime.
- Omnius must pin the exact platform merge commit, bundle digest, delivery profile digest, attestor
  profile digest, public key, and cluster identity before accepting a signature.

## References

- `genai-enablement/docs/decisions/0015-independent-observer-authority-attestor.md`
- `platform-contracts/attestor-profiles/`
- ADR-0056
- ADR-0057
