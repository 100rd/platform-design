# ADR-0020: Kyverno + ValidatingAdmissionPolicy as the policy-engine layer

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — Kyverno + VAP in enforce (#266/#270).
- Date: 2026-06-06
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)

## Context

Cluster-level policy today is two baseline layers: **Pod Security Admission (PSA)
restricted** and a **Cilium NetworkPolicy baseline** (default-deny posture). On top
of that, **Gatekeeper** is live with **4 ConstraintTemplates** and is the most
mature policy component in the estate. **Kyverno is scaffolded but disabled**.

Two things have shifted the trade-off:

- **Kyverno is now CNCF Graduated (2026-03-16, latest v1.18.1)** — production
  maturity is no longer a blocker.
- Kyverno does things Gatekeeper/Rego does awkwardly or not at all: **image
  verification** (cosign), **mutation** (inject `securityContext`), and
  **generation** (create a default-deny NetworkPolicy per namespace) in plain YAML
  rather than Rego.

Separately, the simplest validations (block `:latest`, require resource limits) no
longer need a webhook at all: **ValidatingAdmissionPolicy (VAP)** went **GA in
Kubernetes 1.30** and runs **in-process via CEL** — no admission webhook, no extra
pod on the request path.

There is also a **placement correction** about image-signature verification. The
cosign / Sigstore signing from ADR-0016 must be *verified* somewhere, and the
natural assumption "ArgoCD verifies it" is **wrong**: **ArgoCD can only verify
GnuPG-signed git commits**, not **cosign / OCI image signatures**. So image
verification cannot live in the GitOps sync step — it belongs at **admission**,
where Kyverno's `verifyImages` can check the OCI signature before the pod is
admitted.

## Decision

Deploy **Kyverno as a complement to — not a replacement for — Gatekeeper**, and
push the trivial validations down to **native ValidatingAdmissionPolicy**:

- **Kyverno** owns the policy classes Rego handles poorly:
  - **`verifyImages` (admission-time cosign verification — this is the right
    layer, NOT ArgoCD)** — **keyless** verification against the **Fulcio** identity
    (`issuer` / `subject` of the signing OIDC identity) with **Rekor** transparency
    inclusion, coupling to ADR-0016's signing. **`mutateDigest: true`** rewrites the
    tag reference to the verified **digest** so the admitted pod is pinned to the
    exact verified image. **`failurePolicy: Enforce`** is what makes this a *real
    gate* (Ignore would let unsigned images through on verifier error). Verification
    results are **cached ~60 min** to keep admission latency down. On **Kyverno
    v1.18**, prefer the **Stable `ImageValidatingPolicy`** resource over the older
    `verifyImages` rule form.
  - **mutate** — inject a hardened `securityContext` (drop caps, runAsNonRoot,
    seccomp) so workloads are secure-by-default.
  - **generate** — emit a **default-deny NetworkPolicy** into each namespace.
- **ValidatingAdmissionPolicy (VAP)** owns simple **CEL** validations that need no
  webhook: **block `image: :latest`**, **require CPU/memory limits**. In-process,
  no webhook latency, no controller to keep alive on the admission path. Kyverno can
  also **generate and manage native VAPs** from its own policies — so simple CEL
  validations are **offloaded to the API server** while still being authored/managed
  through Kyverno, rather than each running as a Kyverno webhook call.
- **Gatekeeper stays** — its 4 mature ConstraintTemplates are not rewritten; the
  two engines coexist, each owning what it does best.
- **Rollout is audit-mode first, then `failurePolicy: Enforce` in prod** once
  policies are proven to not block legitimate workloads.

A reviewer can check conformance by confirming Kyverno is enabled with image
verification at **admission** (keyless Fulcio issuer/subject + Rekor,
`mutateDigest: true`, `failurePolicy: Enforce`; `ImageValidatingPolicy` on v1.18)
— **not** delegated to ArgoCD — plus mutate-securityContext / generate-NetworkPolicy
policies, that the `:latest` and require-limits checks run as
`ValidatingAdmissionPolicy` (native, Kyverno-generated where useful, not webhooks),
that Gatekeeper's templates remain, and that prod policies run
`failurePolicy: Enforce`.

## Alternatives considered

### Alternative A: Replace Gatekeeper with Kyverno wholesale
Migrate the 4 ConstraintTemplates to Kyverno and remove Gatekeeper.
Rejected because: the Gatekeeper templates are the most mature policy in the estate
— rewriting working, audited Rego for no functional gain is churn and risk. Coexist
instead; each engine owns its strengths.

### Alternative B: Do everything in Kyverno (including the trivial checks)
Author `:latest`/require-limits as Kyverno policies too.
Rejected because: those are exactly the checks native VAP handles in-process via
CEL with **no webhook** — cheaper and one fewer thing on the admission path. Reserve
Kyverno for verify/mutate/generate, which VAP cannot do.

### Alternative C: Keep PSA + Gatekeeper only (status quo)
Leave Kyverno disabled.
Rejected because: no image-signature enforcement, no secure-by-default mutation, no
generated default-deny NetworkPolicy — all gaps PSA and the 4 templates do not
cover.

## Consequences

### Positive
- Image-signature enforcement at admission (pairs with ADR-0016 cosign signing).
- Secure-by-default workloads via `securityContext` mutation.
- Per-namespace default-deny NetworkPolicy generated automatically.
- Trivial checks run webhook-free via native VAP (lower latency, fewer moving
  parts).
- Gatekeeper's mature templates kept — no rewrite risk.

### Negative
- Two admission engines plus VAP to understand and operate.
- `verifyImages` adds signature-verification latency at admission.

### Risks
- A `Fail`-mode policy could block all deploys cluster-wide. Mitigated by
  **audit-mode first** and per-policy promotion, prod-only `Fail`.
- Mutation that conflicts with a workload's own `securityContext`. Mitigated by
  audit observation before enforce.
- Generated NetworkPolicies colliding with existing Cilium policy. Mitigated by
  validating generation against the ADR baseline in audit first.

## Implementation notes

- Enable the scaffolded Kyverno install (GitOps-managed, pinned to v1.18.1).
- **Image verification (`ImageValidatingPolicy` on v1.18):** keyless, verifying the
  Fulcio identity `issuer`/`subject` from ADR-0016's signing + Rekor; set
  `mutateDigest: true` and `failurePolicy: Enforce` in prod; rely on the ~60-min
  verification cache. This is the verification layer ArgoCD **cannot** provide.
- Kyverno policies: `mutate` securityContext, `generate` default-deny NetworkPolicy.
- VAP: two `ValidatingAdmissionPolicy` + bindings — block `:latest`, require
  limits (CEL); author/manage them as Kyverno-generated VAPs where it reduces
  webhook traffic.
- Rollout: all policies `Audit`/`validationActions: [Audit]` first; promote to
  `Enforce` / `failurePolicy: Enforce` in prod after a clean audit window.

Effort: **M**.

## References

- Kyverno: <https://kyverno.io/docs/>
- Kyverno image verification (`verifyImages` / `ImageValidatingPolicy`, keyless):
  <https://kyverno.io/docs/policy-types/cluster-policy/verify-images/>
- Kyverno generating native VAPs:
  <https://kyverno.io/docs/policy-types/validating-policy/>
- ArgoCD signature verification (GnuPG git commits only):
  <https://argo-cd.readthedocs.io/en/stable/user-guide/gpg-verification/>
- ValidatingAdmissionPolicy (GA 1.30):
  <https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/>
- Related: ADR-0016 (cosign signing — verified here at admission, not in ArgoCD),
  ADR-0003 (Cilium — generated NetworkPolicy)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.*
