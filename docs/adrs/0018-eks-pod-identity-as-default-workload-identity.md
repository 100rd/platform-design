# ADR-0018: EKS Pod Identity as the default workload identity (IRSA becomes legacy)

- Status: **Accepted** — **Implemented** (epic #252); research-backed + doc-verified.
- Ratified: 2026-06-07 by platform owner.
- platform-design status: **implemented** — Pod Identity + ESO 2.6 across workloads (#254/#267/#269).
- Date: 2026-06-06
- Authors: platform-team, security
- Related issues: epic #252
- Supersedes: (none)
- Superseded by: (none)
- Partially supersedes: the IRSA-as-default *mechanism* of infra ADR-006.

## Context

Workloads on the EKS clusters obtain AWS credentials today via **IRSA** (IAM Roles
for Service Accounts): roughly **6 IRSA roles per cluster**, each bound to a
ServiceAccount by the `eks.amazonaws.com/role-arn` annotation, and each cluster
runs its **own OIDC provider** (`enable_irsa = true`). That model has three costs:

- The trust chain is per-cluster: every cluster needs its own OIDC provider
  registered as an IAM identity provider, and a role's trust policy hard-codes that
  provider's issuer URL — so a role is **not portable across clusters**.
- Least-privilege is expressed as *role-per-workload*, which multiplies IAM roles.
- The `eks-pod-identity-agent` addon is **already installed** on the clusters, so
  the newer mechanism is one association away — the prerequisite is already paid
  for.

## Decision

Make **EKS Pod Identity the default workload-identity mechanism**, expressed as
`PodIdentityAssociation` resources (ServiceAccount ↔ IAM role, no OIDC issuer in
the trust policy). The `eks-pod-identity-agent` addon is **already installed** on
the clusters — verified — so the prerequisite is paid for. **IRSA becomes legacy**
and remains supported during **coexistence**. Specifically:

- The Pod Identity role's **trust policy targets the EKS Auth service principal**
  `pods.eks.amazonaws.com`, with **both** `sts:AssumeRole` **and**
  `sts:TagSession` allowed (TagSession is required for EKS to inject the ABAC
  session tags) — *not* a cluster-specific OIDC issuer.
- The **per-cluster OIDC provider is removed** once a cluster's workloads are fully
  migrated (`enable_irsa` no longer required for those clusters).
- **One IAM role is reused across clusters** (the trust targets the EKS service
  principal, not a per-cluster OIDC issuer), collapsing role-per-cluster
  duplication.
- **Least-privilege moves to ABAC** on the **six session tags EKS injects** —
  `eks-cluster-arn`, `eks-cluster-name`, `kubernetes-namespace`,
  `kubernetes-service-account`, `kubernetes-pod-name`, `kubernetes-pod-uid` —
  instead of cutting a new role per workload. A single role with condition-scoped
  policies replaces many narrow roles.
- **Cross-account** access uses `targetRoleArn` on the association (the pod-bound
  role assumes a role in the target account). Cross-account Pod Identity reached
  **GA 2025-06**; the assumed-role credentials are **cached for ~59 minutes**, so
  the target role's trust and permissions must be stable within that window.

**Coexistence caveat — do NOT configure both on one ServiceAccount.** The
precedence when a single ServiceAccount carries **both** an IRSA annotation **and**
a Pod Identity association is **undocumented** by AWS — so we treat "both at once"
as unsupported and remove the IRSA annotation as the final per-workload migration
step rather than relying on an assumed precedence.

**GitHub Actions OIDC is out of scope** — that federation (ADR-0015's central
ECR-push role) stays as-is; this ADR is only about in-cluster pod identity.

### Sub-decision: External Secrets Operator on Pod Identity + Generators/PushSecret

ESO (ADR-0008) is a primary consumer of workload identity, with two doc-verified
wrinkles:

- **ESO supports Pod Identity but cannot use `serviceAccountRef`.** With Pod
  Identity the agent injects credentials into the operator's pod directly; ESO's
  per-SecretStore `serviceAccountRef` (the IRSA-style "act as this SA" indirection)
  is **not** the Pod Identity path. So ESO uses the identity bound to its **own**
  controller ServiceAccount via a `PodIdentityAssociation`, not `serviceAccountRef`.
- **ESO Generators + PushSecret are adopted to cover two rotation flows that need
  no Vault:**
  - **`ECRAuthorizationToken` generator** — mints short-lived ECR pull credentials
    on demand (no static registry secret to rotate).
  - **`Password` generator → `PushSecret`** — generates a credential and **pushes**
    it **into AWS Secrets Manager**, giving in-cluster-originated rotation.
  Neither of these needs HashiCorp Vault — **only `VaultDynamicSecret` requires
  Vault**, and we are not adopting it here.

**Prerequisite — ESO upgrade.** ESO latest is **v2.6.0**; this estate runs
**0.10.5**. The Generators/PushSecret + Pod Identity behaviour above is gated on
upgrading ESO first, and **the v2 line moves the CRDs to `v1`** — so the upgrade is
a CRD-version migration, not a values bump, and must precede the ESO migration step.

A reviewer can check conformance by confirming workload ServiceAccounts are bound
via `PodIdentityAssociation` (not `eks.amazonaws.com/role-arn` annotations), that
the Pod Identity trust targets `pods.eks.amazonaws.com` with `sts:AssumeRole` +
`sts:TagSession`, that migrated clusters no longer register an OIDC provider, that
policies scope on the injected six session tags, that ESO runs on Pod Identity via
its own controller SA (no `serviceAccountRef`) with the ECR/PushSecret generators,
and that no ServiceAccount carries both an IRSA annotation and an association.

## Alternatives considered

### Alternative A: Stay on IRSA
Keep `enable_irsa = true` and annotation-bound roles.
Rejected because: roles stay non-portable (per-cluster OIDC issuer baked into
trust), role-per-workload sprawl continues, and we leave the already-installed
`eks-pod-identity-agent` unused.

### Alternative B: Pod Identity but keep role-per-workload (no ABAC)
Adopt associations but mint a role per workload as before.
Rejected because: it captures portability but not the role-count reduction. ABAC on
injected session tags is the mechanism that lets one role serve many workloads
safely.

### Alternative C: Big-bang cutover
Migrate all addons/workloads to Pod Identity in one change.
Rejected because: identity is on the critical path; a staged cutover with IRSA
coexistence (Pod Identity takes precedence) lets us migrate and verify one consumer
at a time.

## Consequences

### Positive
- Portable roles: one role reused across clusters; no per-cluster OIDC provider to
  maintain.
- Fewer IAM roles via ABAC on injected session tags instead of role-per-workload.
- Uses the already-installed `eks-pod-identity-agent` addon.
- Cross-account via `targetRoleArn` without per-account OIDC trust plumbing.

### Negative
- A migration window where both mechanisms coexist (extra reasoning until IRSA is
  retired per cluster).
- ABAC policies are condition-heavy — a class of bug (wrong tag key/case) that
  role-per-workload did not have.

### Risks
- **Fargate does NOT support Pod Identity.** Any Fargate-scheduled workload must
  stay on IRSA — verify the profile before migrating. (The agent is a node-level
  DaemonSet; Fargate has no node to run it on.)
- **Karpenter-provisioned nodes** must run the agent / support the association
  path; verify Karpenter node images and the agent DaemonSet land on new nodes
  before cutover.
- **Both-mechanisms-on-one-SA precedence is undocumented.** Rather than rely on an
  assumed winner, treat configuring both as unsupported and remove the IRSA
  annotation as the final per-workload migration step.
- **ESO v2 CRD migration (v1 CRDs) and the 0.10.5 → v2.6.0 jump.** A multi-major
  upgrade with a CRD-group change; stage it in a non-prod cluster before migrating
  ESO onto Pod Identity.

## Implementation notes

- Express associations as `PodIdentityAssociation` (Terraform / addon values),
  ServiceAccount-scoped. Trust `pods.eks.amazonaws.com` with `sts:AssumeRole` +
  `sts:TagSession`.
- **Prereq:** upgrade ESO 0.10.5 → v2.6.0 (CRDs move to `v1`) before migrating ESO.
- **Cutover order:** `YACE` (CloudWatch exporter) → observability stack →
  External Secrets Operator (ESO, on its own controller SA — no `serviceAccountRef`)
  → AWS Load Balancer controller. Lowest-blast-radius consumers first;
  ingress-critical LB controller last. Skip any Fargate-scheduled workload.
- After a cluster's consumers are migrated, drop its OIDC provider and
  `enable_irsa`.
- ABAC base role: trust the EKS service principal; attach policies scoped by
  `aws:PrincipalTag/eks-cluster-arn`, `.../eks-cluster-name`,
  `.../kubernetes-namespace`, `.../kubernetes-service-account`,
  `.../kubernetes-pod-name`, `.../kubernetes-pod-uid`.
- **ESO Generators:** `ECRAuthorizationToken` (short-lived ECR pull creds) and
  `Password` generator → `PushSecret` into Secrets Manager. No Vault needed (only
  `VaultDynamicSecret` would).

Effort: **M**.

## References

- EKS Pod Identity:
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html>
- Pod Identity vs IRSA / ABAC session tags:
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html>
- Cross-account Pod Identity (`targetRoleArn`, GA 2025-06):
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-id-cross-account.html>
- External Secrets Operator — Generators / PushSecret:
  <https://external-secrets.io/latest/api/generator/>
- Related: ADR-0006 (ArgoCD), ADR-0007 (Karpenter), ADR-0008 (External Secrets
  Operator)

---
*Research-backed + doc-verified 2026-06-07 (Context7 + official AWS/vendor docs) —
2026 platform modernization; grounded in infra@572b54d / argocd@c364c6c. Accepted,
ratified 2026-06-07 by platform owner; not yet implemented in platform-design.
Partially supersedes the IRSA-auth mechanism of infra ADR-006.*
