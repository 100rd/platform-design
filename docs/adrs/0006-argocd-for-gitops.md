# ADR-0006: ArgoCD for GitOps delivery of Kubernetes workloads

- Status: **Accepted** — decision is *adopted (live in source estate)*
- Date: 2026-06-03
- Authors: platform-team
- Related issues: (ported)
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform's AWS control-plane workloads (GitOps orchestration, observability
stack, the LiteLLM/inference gateway front-end, public APIs) are deployed to EKS.
The edge tier's agent rollout is also promotion-driven from Git. We need a GitOps
tool that continuously reconciles desired state from Git and self-heals drift.
Options:

1. **ArgoCD** — declarative GitOps with a UI.
2. **Flux** — CNCF GitOps toolkit.
3. **Terraform-only** — manage K8s resources via Terraform.

## Decision

Use **ArgoCD** for all Kubernetes workload delivery, in an app-of-apps layout
(`bootstrap/root-app` → ApplicationSets per cluster-role/infra/observability/
workloads). A reviewer can check conformance by confirming new workloads are
delivered as ArgoCD `Application`/`ApplicationSet` definitions rather than
`kubectl apply` or Terraform-managed manifests.

## Alternatives considered

### Alternative A: Flux v2
Controller-based CNCF GitOps toolkit.
Rejected because: no built-in UI, and the controller-per-concern model is more
complex for teams newer to GitOps. ArgoCD's dashboard is load-bearing for
developer self-service across multiple product domains.

### Alternative B: Terraform-only
Render and apply Kubernetes manifests from Terraform.
Rejected because: Terraform is not designed for continuous reconciliation. Drift
detection and self-healing require a watch loop, which ArgoCD provides and
Terraform does not.

### Alternative C: Status quo
Greenfield — "status quo" is no continuous delivery (manual `kubectl`), which
fails the self-healing / auditability requirement.

## Consequences

### Positive
- The web UI gives immediate visibility into sync status, diffs, and history —
  essential for self-service across the platform's product teams.
- `ApplicationSet` templating drives multi-environment, multi-cluster delivery
  from one definition (see ADR-0012 for the cluster-selector label scheme).
- Sync waves and hooks order deployments (CRDs before workloads, migrations
  before apps) without external orchestration.
- Project/application RBAC integrates with SSO; teams manage their own apps
  without cluster-admin.
- Large ecosystem (notifications, image updater, Argo Rollouts integration — see
  ADR-0014).

### Negative
- Another component to operate and upgrade on-cluster.
- CRD-management complexity (ArgoCD's own CRDs plus application CRDs).
- Secrets are handled out-of-band via External Secrets Operator (ADR-0008) —
  ArgoCD does not natively manage encrypted secrets in Git.
- Resource overhead: argocd-server, repo-server, application-controller pods.

### Risks
- Teams must learn ArgoCD concepts (sync policies, health checks). Mitigated by
  the app-of-apps convention and reference values charts.

## Implementation notes

- App-of-apps via `bootstrap/root-app`; ApplicationSets for cluster-roles, infra,
  observability, and workloads.
- Secrets via ESO `ClusterSecretStore` (ADR-0008); progressive delivery via Argo
  Rollouts (ADR-0014).
- CI integrates by opening PRs into the GitOps repo that bump image tag/digest
  (ADR-0015).

## References

- ArgoCD docs: <https://argo-cd.readthedocs.io/>
- Ported from `infra` ADR-004 (ArgoCD for GitOps) and `argocd`
  app-of-apps layout
- Related: ADR-0008 (ESO), ADR-0012 (cluster-role labels), ADR-0014 (Argo
  Rollouts), ADR-0015 (reusable CI pipelines)

---
*Ported from infra@572b54d (and argocd@c364c6c) during the 2026-06
platform-design sync. Decision status in the source estate: adopted (live).*
