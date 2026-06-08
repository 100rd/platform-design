# ADR-0034: Backstage as the Internal Developer Platform

- Status: **Proposed — Deferred (on hold)**
- Deferred: 2026-06-08 by platform owner — revisit when a dedicated owner is
  assigned and the platform backlog matures.
- platform-design status: **pending** — no Backstage installation or catalog
  config exists in this repo.
- Date: 2026-06-08
- Authors: platform-team
- Related issues: epic [#252](https://github.com/100rd/platform-design/issues/252)
- Supersedes: (none)
- Superseded by: (none)

## Context

The platform now has a well-defined set of standards encoded in ADRs: the generic
Helm/app chart (ADR-0006, ADR-0014), ArgoCD/Kargo promotion (ADR-0006, ADR-0021),
Kyverno keyless-signed images (ADR-0020), EKS Pod Identity (ADR-0018), and the
observability wiring (ADR-0026). At the same time, onboarding a new service
requires developers to stitch these pieces together manually — there is no
single pane that shows what services exist, who owns them, and how to scaffold a
new one that conforms to the ADRs from day one.

Backstage is the CNCF-graduated Internal Developer Platform adopted by many
platform-engineering organisations for exactly this: a **Software Catalog**
(register and browse services, their owners, dependencies, and ADR compliance)
and **Golden Path Scaffolder templates** (generate a service that is already
wired to the platform's patterns).

The strategic fit is strong. However, Backstage is **not a Helm-install-and-forget
tool**: it is a self-owned Node.js application that requires a dedicated
engineering owner to maintain the app itself, its plugins, and its
`catalog-info.yaml` conventions across the organisation. As of 2026-06-08, no
such owner has been assigned, and taking on the operational commitment without one
would result in an abandoned or degraded portal within months.

## Decision

**Backstage as the Internal Developer Platform is deferred / on hold.**

The decision to adopt Backstage is strategically sound and is not rejected; it is
placed on hold until:

1. A **dedicated owner** (team or engineer) is assigned to operate Backstage as a
   product — managing the Node.js app, plugin upgrades, and catalog hygiene.
2. The **platform backlog matures** such that the Golden Path Scaffolder template
   can reference a stable, implemented set of ADRs rather than tracking pending
   items.

### Agreed Phase 1 scope (to execute when the hold is lifted)

When revisited, the Phase 1 implementation is bounded to:

- **Software Catalog**: register all existing services via `catalog-info.yaml`
  files (Kind: Component, System, API). No manual imports; catalog populated
  from SCM discovery.
- **ONE Golden Path Scaffolder template**: generates a new service pre-wired to:
  - the generic Helm/app chart (ADR-0006),
  - ArgoCD + Kargo GitOps promotion (ADR-0006, ADR-0021),
  - Kyverno keyless-signed images (ADR-0020),
  - EKS Pod Identity for AWS access (ADR-0018),
  - observability wiring — metrics, structured logs, traces (ADR-0026).
- **Three plugins** (no more in Phase 1): ArgoCD plugin (sync status),
  Kubernetes plugin (pod/rollout health), OpenCost plugin (per-service cost
  — ADR-0027).
- **TechDocs deferred to Phase 2**: Backstage-rendered docs are desirable but
  add maintenance surface; defer until Phase 1 is stable.

A reviewer can check Phase 1 conformance by confirming: `catalog-info.yaml` files
exist for all services, the scaffolder template generates a repo that passes
the platform CI supply-chain gates (ADR-0016), and the three plugins are
registered and returning data.

## Alternatives considered

### Alternative A: Self-hosted Backstage (chosen — if hold is lifted)

Deploy Backstage on the platform EKS cluster, managed as a first-class
GitOps-delivered application (ArgoCD ApplicationSet, ADR-0006). The operator
owns the Node.js app, its Docker image, and plugin upgrades.

**Chosen for Phase 1 if the hold is lifted** — full control, no vendor lock-in,
aligns with the estate's self-hosted-first posture.

### Alternative B: Managed Backstage (Roadie / Spotify Portal)

SaaS-hosted Backstage. Eliminates the Node.js operational burden; the vendor
manages upgrades and infrastructure.

Rejected (for now) because: adds an external SaaS dependency and ongoing
subscription cost. Revisit if the dedicated-owner constraint cannot be met
and the catalog value is urgent enough to justify the spend.

### Alternative C: Lighter SaaS IDP (Port / Cortex)

Port and Cortex offer catalog + scorecard + self-service without the Node.js
self-hosting burden. Both are SaaS-native.

Deferred: the strategic preference is Backstage (CNCF-graduated, open ecosystem,
no lock-in). Port/Cortex become relevant if the self-hosted and managed-Backstage
paths are both ruled out.

## Consequences

### Positive
- Phase 1 scope is deliberately small (catalog + one template + three plugins) —
  reduces the ramp-up for the dedicated owner and delivers immediate value
  without sprawl.
- Golden Path template encodes ADR conformance at creation time, not as a
  post-hoc audit.
- OpenCost plugin (ADR-0027) surfaces per-service cost in the catalog, closing
  the FinOps loop.

### Negative
- Until the hold is lifted, developers must onboard services manually against
  the ADR checklist. The gap in self-service UX remains.
- Backstage's Node.js runtime adds a non-Kubernetes workload to the platform
  maintenance surface once adopted.

### Risks
- **Ownership risk**: the primary non-technical risk. Mitigated by making the
  hold condition explicit — no deployment until an owner is formally assigned.
- **Scope creep after lift**: Phase 1 scope must be enforced; TechDocs and
  additional plugins inflate the maintenance surface quickly. Mitigated by the
  Phase 1 boundary defined above.
- **Plugin compatibility drift**: Backstage's plugin ecosystem moves fast;
  pinning plugin versions and gating upgrades in CI mitigates breakage.

## Implementation notes

- When the hold is lifted, start from the
  [Backstage `@backstage/create-app` scaffold](https://backstage.io/docs/getting-started/)
  and deploy via the generic Helm/app chart (ADR-0006) under a dedicated
  `backstage` ArgoCD Application.
- `catalog-info.yaml` convention: adopt the
  [Backstage System model](https://backstage.io/docs/features/software-catalog/system-model)
  (Domain → System → Component → API).
- The Scaffolder template repository lives in the platform-design org and is
  itself catalog-registered.
- Secrets (GitHub token for SCM discovery, plugin API tokens) delivered via
  ESO from Secrets Manager (ADR-0008).
- CI gate: the generated scaffolder output must pass `helm lint`,
  `kubeconform`, and the Tier-1 supply-chain scan (ADR-0016).

Effort (Phase 1, when hold is lifted): **XL** — dominated by Node.js app setup
and catalog population, not by the template itself.

## References

- Backstage getting started: <https://backstage.io/docs/getting-started/>
- Backstage Software Catalog: <https://backstage.io/docs/features/software-catalog/>
- Backstage Scaffolder: <https://backstage.io/docs/features/software-templates/>
- Backstage ArgoCD plugin: <https://backstage.io/docs/integrations/argocd/>
- Backstage Kubernetes plugin: <https://backstage.io/docs/features/kubernetes/>
- Roadie (managed Backstage): <https://roadie.io/>
- Port (alternative SaaS IDP): <https://www.getport.io/>
- Cortex (alternative SaaS IDP): <https://www.cortex.io/>
- Related: ADR-0006 (ArgoCD GitOps — delivery of Backstage itself),
  ADR-0008 (ESO — secrets for plugins),
  ADR-0016 (Tier-1 supply-chain hardening — gates on generated repos),
  ADR-0018 (EKS Pod Identity — Backstage AWS access),
  ADR-0020 (Kyverno — keyless signing wired by the Golden Path template),
  ADR-0021 (Kargo — promotion wired by the Golden Path template),
  ADR-0026 (Observability — wired by the Golden Path template),
  ADR-0027 (OpenCost — plugin Phase 1),
  epic #252.

---
*Proposal — owner discussion 2026-06-08. Status: Proposed — Deferred (on hold).
Revisit trigger: dedicated Backstage owner assigned + platform backlog matures.*
