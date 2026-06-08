# Platform-Design Roadmap

Phased delivery plan for the platform-design repo. Tracks **GATE** umbrella
issues (multi-issue initiatives) and the per-phase issue list with explicit
dependencies.

This file replaces the unstructured `PLAN.md` (kept for backwards-compatible
historical context — covers transaction-analytics work, see `docs/transaction-
analytics/`) and the granular `TODO.md` (kept as a per-task checklist working
file). Issue #183.

> **ADRs govern decisions; ROADMAP tracks work.** Each phase and GATE below cites
> the ADR number(s) that govern its decisions — see the catalog and the
> per-ADR **platform-design status** (`synced` / `partial` / `pending`) in
> [`docs/adrs/README.md`](docs/adrs/README.md). When an ADR is `partial` or
> `pending`, the gap is the work this ROADMAP tracks; when a phase introduces a
> new controversial trade-off, file an ADR first and link it here.

## Phase status legend

- DONE — landed on `main`, has tests and runbook
- IN PROGRESS — branch exists, CI green on at least one slice
- PLANNED — scoped but not started
- BLOCKED — has an upstream dependency

---

## Phase 0 — Foundation (DONE)

Initial multi-account AWS, EKS, observability, GitOps stack. See `docs/02-terragrunt-strategy.md` and `PROJECT_STATUS.md` for the inventory.

---

## Phase 1 — Landing zone (DONE / IN PROGRESS)

GATE umbrella: **#207 [GATE] Landing Zone Done**.

Governing ADRs: [ADR-0001](docs/adrs/0001-ou-split.md) (OU split),
[ADR-0005](docs/adrs/0005-hub-spoke-transit-gateway.md) (hub-spoke TGW),
[ADR-0011](docs/adrs/0011-break-glass-iam-destroy-protection.md) (break-glass —
`partial`: SSO/procedure model, no break-glass-user `prevent_destroy` yet),
[ADR-0013](docs/adrs/0013-inter-vpc-access-security-model.md) (inter-VPC model —
`pending`, tracked by #243).

| # | Title | Status |
|---|-------|--------|
| #156 | Unify Terragrunt root skeleton (`_envcommon`, `common.hcl`, `versions.hcl`) | DONE |
| #157 | Multi-account Control Tower account structure | DONE |
| #158 | OU split (Production / Non-Production / Deployments / Suspended / Sandbox) | DONE |
| #159 | State backend bootstrap (TF-only) | DONE (PR #189) |
| #160 | Cross-region DR for Terraform state | DONE (PR #190) |
| #161 | cloudtrail-org wrapper | DONE (PR #193) |
| #162 | config-org wrapper + aggregator + conformance pack | DONE (PR #196) |
| #163 | GuardDuty findings publishing destination | DONE (PR #194) |
| #164 | securityhub-org + delegated admin | DONE (PR #197) |
| #165 | IAM baseline + root access-key alarm | DONE (PR #195) |
| #166 | SCPs + data perimeter | DONE (PR #192) |
| #167 | SSO Identity Center | DONE (PR #191) |
| #168 | Account Factory for Terraform (AFT) for account vending | PLANNED |
| #169 | Break-glass procedure for root account access | DONE |
| #173 | Scope-down Terraform CI/CD IAM role (no `AdministratorAccess`) | PLANNED |

**Phase exit criteria**: every issue in the GATE checklist closed. Currently 12 of 15 closed.

---

## Phase 2 — Networking (PLANNED)

Governing ADRs: [ADR-0005](docs/adrs/0005-hub-spoke-transit-gateway.md) (hub-spoke
TGW — `synced`),
[ADR-0013](docs/adrs/0013-inter-vpc-access-security-model.md) (inter-VPC security
model incl. the inspection VPC — `pending`, tracked by #243).

| # | Title | Status | Depends on |
|---|-------|--------|-----------|
| #170 | Transit Gateway hub-and-spoke (modules: `transit-gateway`, `tgw-attachment`) | DONE | #157 |
| #171 | Centralized egress/ingress inspection VPC (GWLB + Network Firewall) | PLANNED | #170 |

---

## Phase 3 — CI/CD hardening (IN PROGRESS)

GATE umbrella: **#208 [GATE] CI/CD Hardened**.

Governing ADRs: [ADR-0015](docs/adrs/0015-reusable-ci-pipelines.md) (reusable
CI/CD pipelines) and
[ADR-0016](docs/adrs/0016-tier1-supply-chain-hardening.md) (Tier-1 hardening) —
both **Accepted — rolling out**, implemented in-repo by #241 (`synced`); the
org-wide `@v1` fan-out and the dep-scan/SAST composite actions are the remaining
design-target.

| # | Title | Status | Depends on |
|---|-------|--------|-----------|
| #172 | Consolidate CI workflows (`terraform-checks` / `plan` / `apply`) | PLANNED | — |
| #173 | Scope-down Terraform CI/CD IAM role | PLANNED | #172 (see GATE) |
| #174 | Pinned tool versions (`.terraform-version`, `.terragrunt-version`) | DONE | #156 |
| #177 | GitHub branch protection as Terraform module | DONE | — |
| #179 | Version Matrix (single source for tools/modules/providers) | DONE | #156 |
| #180 | Make Slack notifications conditional in CI workflows | DONE | — |
| #187 | Two-step rollout pattern (build modules then apply to accounts) | PLANNED | #172 |

**Phase exit criteria**: every issue in #208 closed.

---

## Phase 4 — Cost & operations (IN PROGRESS)

Governing ADRs: [ADR-0001](docs/adrs/0001-ou-split.md) (per-account / per-OU cost
allocation underpins per-account budgets),
[ADR-0004](docs/adrs/0004-terragrunt-over-plain-terraform.md) (the
`generate "provider"` `default_tags` that drive cost-allocation tags).

| # | Title | Status |
|---|-------|--------|
| #175 | AWS Budgets module + per-account cost alerts | DONE |
| #181 | Orphaned resource detection & cleanup module | PLANNED |

---

## Phase 5 — Observability extensions (PLANNED)

Governing ADRs: [ADR-0001](docs/adrs/0001-ou-split.md) (the Security / Log-Archive
account the org-wide log pattern lands in),
[ADR-0006](docs/adrs/0006-argocd-for-gitops.md) (observability stack is delivered
as ArgoCD ApplicationSets).

| # | Title | Status | Depends on |
|---|-------|--------|-----------|
| #178 | Centralized EKS audit & authenticator log aggregation | PLANNED | #160 (DR state), #182 (log-archive bucket policy) |
| #182 | Centralized logging module (org-wide log-archive pattern) | PLANNED | #157 (log-archive account exists) |

---

## Phase 6 — EKS data plane (PLANNED)

Governing ADRs: [ADR-0003](docs/adrs/0003-cilium-over-aws-vpc-cni.md) (Cilium CNI
— `synced`; #186 mTLS extends it),
[ADR-0007](docs/adrs/0007-karpenter-over-cluster-autoscaler.md) (Karpenter —
`synced`),
[ADR-0009](docs/adrs/0009-cilium-gateway-api-ingress.md) (Cilium Gateway API
ingress — `partial`: only HTTPRoute scaffolding, cluster ingress still
nlb-ingress),
[ADR-0014](docs/adrs/0014-argo-rollouts-canary-progressive-delivery.md) (Argo
Rollouts canary — `synced`, #238).

| # | Title | Status |
|---|-------|--------|
| #185 | Velero for Kubernetes backup/migration | PLANNED |
| #186 | Cilium mTLS pod-to-pod encryption | PLANNED |

---

## Phase 7 — Documentation & process (DONE / IN PROGRESS)

Governing ADRs: [ADR-0011](docs/adrs/0011-break-glass-iam-destroy-protection.md)
(break-glass — #169 ships the procedure runbook; the IAM-user `prevent_destroy`
guard is the `partial` remainder). #176 stands up the ADR catalog itself
([`docs/adrs/README.md`](docs/adrs/README.md)).

| # | Title | Status |
|---|-------|--------|
| #169 | Break-glass procedure for root account access | DONE |
| #176 | ADR directory + auto-generated infrastructure diagrams in CI | DONE |
| #183 | Structured ROADMAP.md (this file) | IN PROGRESS |
| #184 | `.editorconfig` + `.trivyignore` in repo root | DONE |
| #188 | GATE umbrella issues skeleton | DONE (#207, #208 created) |

---

## Phase 8 — 2026 Modernization (research-backed + doc-verified; decisions Accepted, implementation PLANNED)

These items came from the **2026 platform-block research** deep-dives — formalized
into eleven ADRs (0017–0027), **all ratified Accepted 2026-06-07 by the platform
owner** and **doc-verified 2026-06-07 (Context7 + official AWS/vendor docs)**. The
decisions are made; **implementation is PLANNED** and each stays `pending` in-repo
until wired in. Tracked under epic
[#252](https://github.com/100rd/platform-design/issues/252).

| # | Title | Decision | Implementation | Governing ADR |
|---|-------|----------|----------------|---------------|
| #252 | Resource-side data perimeter + declarative org controls (AFT vending, RCPs, EC2 Declarative Policies, full-IAM SCPs GA 2025-09-19, Access-Analyzer custom-check gate on JSON `result`) | Accepted | PLANNED | [ADR-0017](docs/adrs/0017-resource-side-perimeter-and-declarative-org-controls.md) |
| #252 | EKS Pod Identity as default workload identity (IRSA → legacy, 6 ABAC session tags, ESO 0.10.5→v2.6.0 prereq) | Accepted | PLANNED | [ADR-0018](docs/adrs/0018-eks-pod-identity-as-default-workload-identity.md) |
| #252 | Harvest Cilium / eBPF capabilities (OBI→Tempo tracing, Hubble UI, Tetragon, ClusterMesh; **netkit pilot** — unblocked on kernel 6.12) | Accepted | PLANNED | [ADR-0019](docs/adrs/0019-harvest-cilium-ebpf-capabilities.md) |
| #252 | Kyverno + ValidatingAdmissionPolicy policy-engine layer (admission-time cosign verify — not ArgoCD; complements Gatekeeper) | Accepted | PLANNED | [ADR-0020](docs/adrs/0020-kyverno-and-vap-policy-engine.md) |
| #252 | Kargo GitOps environment-promotion layer (bump 1.2→1.9, Prometheus analysis gates, OTel SLO-gating design-target) | Accepted | PLANNED | [ADR-0021](docs/adrs/0021-kargo-gitops-promotion-layer.md) |
| #252 | CI supply-chain runtime hardening (zizmor Actions SAST + Harden-Runner egress; Artifact Attestations / Immutable Releases / cosign 2.4 follow-ons; spike #251) | Accepted | PLANNED | [ADR-0022](docs/adrs/0022-ci-supply-chain-runtime-hardening.md) |
| #252 | VPC Lattice resource connectivity — cross-account/cross-VPC TCP resource access (Resource Gateway + `type=ARN` config + RAM + IAM auth) | Accepted | PLANNED | [ADR-0023](docs/adrs/0023-vpc-lattice-resource-connectivity.md) |
| #252 | ArgoCD operational hardening (PreDelete hooks, shallow clone, server-side diff/apply, progressive ApplicationSet rollout — no upgrade) | Accepted | PLANNED | [ADR-0024](docs/adrs/0024-argocd-operational-hardening.md) |
| #252 | Envoy Gateway secondary L7 GatewayClass alongside Cilium (rate-limit / ext-proc / WASM / circuit-breaking) | Accepted | PLANNED | [ADR-0025](docs/adrs/0025-envoy-gateway-secondary-l7.md) |
| #252 | Observability target architecture (LGTM: Prometheus 3 + Thanos, Loki, Tempo, Alloy; one RED source; no Mimir/Coroot) | Accepted | PLANNED | [ADR-0026](docs/adrs/0026-observability-target-architecture.md) |
| #252 | Kubernetes cost allocation via OpenCost + AWS CUR/Athena (amortized, discount-aware; optional Kubecost Free) | Accepted | PLANNED | [ADR-0027](docs/adrs/0027-kubernetes-cost-opencost-cur.md) |

### Batch-B ADRs (0029–0032) — implemented 2026-06-08

ADRs 0029–0032 were proposed, doc-verified, and implemented this session
(2026-06-08) under epic [#252](https://github.com/100rd/platform-design/issues/252).
Their modules and Helm templates are `synced` in-repo; no live AWS resources have
been applied yet.

| ADR | Title | Implementation status |
|-----|-------|-----------------------|
| [ADR-0029](docs/adrs/0029-ecr-pull-through-cache.md) | ECR Pull-Through Cache for public upstream registries | synced (module) — not applied |
| [ADR-0030](docs/adrs/0030-bottlerocket-node-os.md) | Bottlerocket as the EKS node operating system | synced (module) / pending (manifests) |
| [ADR-0031](docs/adrs/0031-secret-rotation.md) | Automated secret rotation via Secrets Manager rotation Lambda + ESO auto-refresh | synced (module) — not applied |
| [ADR-0032](docs/adrs/0032-db-migrations-gitops.md) | DB migrations via ArgoCD PreSync Jobs | synced (helm) — not applied |

### ADR-0034 Backstage IDP — Proposed, Deferred (on hold)

[ADR-0034](docs/adrs/0034-backstage-idp.md) records the **Backstage Internal
Developer Platform** decision, tracked by epic
[#252](https://github.com/100rd/platform-design/issues/252). Backstage is a strong
strategic fit — it would provide a Software Catalog and a Golden Path Scaffolder
template that generates services pre-wired to the platform ADRs. The decision is
**deferred / on hold** as of 2026-06-08 by the platform owner because Backstage is
a self-owned Node.js application (not a Helm-install), and taking on the operational
commitment without a dedicated owner would result in degradation.

**Agreed Phase 1 scope** (when hold is lifted):

- Software Catalog (`catalog-info.yaml` registration for all services).
- ONE Golden Path Scaffolder template generating a new service conforming to the
  platform ADRs: generic Helm/app chart + ArgoCD/Kargo promotion (ADR-0006,
  ADR-0021) + Kyverno keyless-signed images (ADR-0020) + EKS Pod Identity
  (ADR-0018) + observability wiring (ADR-0026).
- Three plugins only: ArgoCD (sync status), Kubernetes (pod/rollout health),
  OpenCost (per-service cost, ADR-0027).
- TechDocs deferred to Phase 2.

**Revisit trigger**: a dedicated Backstage owner is assigned and the platform
backlog (ADRs 0017–0027) matures toward `synced`.

### Candidates / revisit (considered, NOT accepted)

Recorded in ADR-0025's alternatives — tracked, not adopted:

- **AWS Load Balancer Controller Gateway API v3.0** (ALB `gateway.k8s.aws/alb` +
  NLB `gateway.k8s.aws/nlb`, GA 2026-01-23; coexists with Cilium). Deferred because
  the estate is NLB-only and Argo Rollouts' AWS-native canary is ALB-Ingress-based,
  not Gateway-API — **revisit when ALB enters**.
- **GAMMA on Cilium** (east-west `HTTPRoute`→`Service`; Cilium GAMMA v1.0.0
  Core + 2/3 Extended, producer-only / same-namespace, no consumer routes,
  experimental). **Revisit as Cilium's GAMMA support matures.**

**Phase exit criteria**: each ADR is ratified (done — Accepted 2026-06-07) and its
decision wired in-repo (`pending` → `synced`).

---

## GATE umbrella issues

| GATE | Issue | Children | Governing ADRs | Status |
|---|---|---|---|---|
| Landing Zone Done | [#207](https://github.com/100rd/platform-design/issues/207) | #156-167, #168-169, #173 | ADR-0001, 0005, 0011, 0013 | 12/15 done |
| CI/CD Hardened | [#208](https://github.com/100rd/platform-design/issues/208) | #172, #173, #177, #180, #187 | ADR-0015, 0016 | 2/5 done |

Add new GATE umbrellas in pull-requests when initiating any multi-issue effort that spans more than 3 children.

---

## Cross-cutting decisions

ADRs live in `docs/adrs/` — see the [index](docs/adrs/README.md) for the full
catalog (0001–0032, 0034) with each ADR's **platform-design status**. ADRs 0017–0027
are the **2026 modernization** set: research-backed + doc-verified 2026-06-07, all
ratified **Accepted** (implementation `pending` / PLANNED, tracked by Phase 8 above).
ADRs 0029–0032 are the **Batch-B** set: implemented 2026-06-08 (`synced` in modules /
charts). ADR-0034 (Backstage) is **Proposed — Deferred (on hold)** — see Phase 8
above. The two native foundation ADRs:
- [ADR-0001 OU split](docs/adrs/0001-ou-split.md) — explains why `Prod` / `NonProd` aliases were preserved instead of renaming to canonical `Production` / `Non-Production`.
- [ADR-0002 TF-only state backend bootstrap](docs/adrs/0002-tf-only-state-backend.md) — bootstrap chicken-and-egg resolution.

ADRs 0003–0016 were ported from the source-of-truth estate during the 2026-06
sync; 0015/0016 (CI/CD) are implemented in-repo by #241. The per-ADR
**platform-design status** column flags where the mock still lags a decision
(`partial`/`pending`) — those rows are the work the phases above track
(notably 0009 ingress, 0010 prod allow-list, 0011 break-glass guard, 0013
inter-VPC tracked by #243).

When a phase introduces a controversial trade-off, file an ADR. The 7-section template at `docs/adrs/0000-template.md` keeps the format consistent.

---

## Companion documents

| File | Purpose |
|---|---|
| `PLAN.md` | Transaction-analytics phased build plan (different scope from this roadmap; preserved for context). |
| `TODO.md` | Granular per-task checklist (developer working file; not a release artefact). |
| `PROJECT_STATUS.md` | Snapshot status: tech-stack versions, recent PRs, pending work. |
| `docs/version-matrix.md` | Single-source pin list for tools / modules / providers. |
| `docs/ou-structure.md` | OU hierarchy + SCP attachment matrix. |
| `docs/break-glass-procedure.md` | Root-account access runbook. |
