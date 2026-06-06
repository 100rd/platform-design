# ADR-0018: EKS Pod Identity as the default workload identity (IRSA becomes legacy)

- Status: **Proposed** — research-backed; decision to ratify, not yet
  implemented.
- platform-design status: **pending** — workloads still bind identity via IRSA
  annotations; no `PodIdentityAssociation` resources are wired in.
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
the trust policy). **IRSA becomes legacy** and remains supported during
coexistence; where both exist for the same ServiceAccount, **Pod Identity takes
precedence**. Specifically:

- The **per-cluster OIDC provider is removed** once a cluster's workloads are fully
  migrated (`enable_irsa` no longer required for those clusters).
- **One IAM role is reused across clusters** (the Pod Identity trust policy targets
  the EKS service principal, not a cluster-specific OIDC issuer), collapsing the
  role-per-cluster duplication.
- **Least-privilege moves to ABAC** on the session tags EKS injects —
  `kubernetes-namespace`, `kubernetes-service-account`, and `eks-cluster-name` —
  instead of cutting a new role per workload. A single role with
  condition-scoped policies replaces many narrow roles.
- **Cross-account** access uses `targetRoleArn` on the association (the pod-bound
  role assumes a role in the target account), rather than per-account OIDC trust.

**GitHub Actions OIDC is out of scope** — that federation (ADR-0015's central
ECR-push role) stays as-is; this ADR is only about in-cluster pod identity.

A reviewer can check conformance by confirming workload ServiceAccounts are bound
via `PodIdentityAssociation` (not `eks.amazonaws.com/role-arn` annotations), that
migrated clusters no longer register an OIDC provider, and that policies scope on
the injected `kubernetes-namespace` / `kubernetes-service-account` /
`eks-cluster-name` session tags.

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
- **Fargate does not support Pod Identity.** Any Fargate-scheduled workload must
  stay on IRSA — verify the profile before migrating.
- **Karpenter-provisioned nodes** must run the agent / support the association
  path; verify Karpenter node images and the agent DaemonSet land on new nodes
  before cutover.
- A precedence surprise if a ServiceAccount keeps both an IRSA annotation and an
  association. Mitigated by removing the annotation as the final migration step per
  workload.

## Implementation notes

- Express associations as `PodIdentityAssociation` (Terraform / addon values),
  ServiceAccount-scoped.
- **Cutover order:** `YACE` (CloudWatch exporter) → observability stack →
  External Secrets Operator (ESO) → AWS Load Balancer controller. Lowest-blast-
  radius consumers first; ingress-critical LB controller last.
- After a cluster's consumers are migrated, drop its OIDC provider and
  `enable_irsa`.
- ABAC base role: trust the EKS service principal; attach policies scoped by
  `aws:PrincipalTag/kubernetes-namespace`,
  `aws:PrincipalTag/kubernetes-service-account`, `aws:PrincipalTag/eks-cluster-name`.

Effort: **M**.

## References

- EKS Pod Identity:
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html>
- Pod Identity vs IRSA / ABAC session tags:
  <https://docs.aws.amazon.com/eks/latest/userguide/pod-id-abac.html>
- Related: ADR-0006 (ArgoCD), ADR-0007 (Karpenter), ADR-0008 (External Secrets
  Operator)

---
*Research-backed — 2026 platform modernization; grounded in infra@572b54d /
argocd@c364c6c. Proposed: decision to ratify, not yet implemented in
platform-design. Partially supersedes the IRSA-auth mechanism of infra ADR-006.*
