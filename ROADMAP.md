# Platform-Design Roadmap

Phased delivery plan for the platform-design repo. Tracks **GATE** umbrella
issues (multi-issue initiatives) and the per-phase issue list with explicit
dependencies.

This file replaces the unstructured `PLAN.md` (kept for backwards-compatible
historical context — covers transaction-analytics work, see `docs/transaction-
analytics/`) and the granular `TODO.md` (kept as a per-task checklist working
file). Issue #183.

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

| # | Title | Status | Depends on |
|---|-------|--------|-----------|
| #170 | Transit Gateway hub-and-spoke (modules: `transit-gateway`, `tgw-attachment`) | DONE | #157 |
| #171 | Centralized egress/ingress inspection VPC (GWLB + Network Firewall) | PLANNED | #170 |

---

## Phase 3 — CI/CD hardening (IN PROGRESS)

GATE umbrella: **#208 [GATE] CI/CD Hardened**.

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

| # | Title | Status |
|---|-------|--------|
| #175 | AWS Budgets module + per-account cost alerts | DONE |
| #181 | Orphaned resource detection & cleanup module | PLANNED |

---

## Phase 5 — Observability extensions (PLANNED)

| # | Title | Status | Depends on |
|---|-------|--------|-----------|
| #178 | Centralized EKS audit & authenticator log aggregation | PLANNED | #160 (DR state), #182 (log-archive bucket policy) |
| #182 | Centralized logging module (org-wide log-archive pattern) | PLANNED | #157 (log-archive account exists) |

---

## Phase 6 — EKS data plane (PLANNED)

| # | Title | Status |
|---|-------|--------|
| #185 | Velero for Kubernetes backup/migration | PLANNED |
| #186 | Cilium mTLS pod-to-pod encryption | PLANNED |

---

## Phase 7 — Documentation & process (DONE / IN PROGRESS)

| # | Title | Status |
|---|-------|--------|
| #169 | Break-glass procedure for root account access | DONE |
| #176 | ADR directory + auto-generated infrastructure diagrams in CI | DONE |
| #183 | Structured ROADMAP.md (this file) | IN PROGRESS |
| #184 | `.editorconfig` + `.trivyignore` in repo root | DONE |
| #188 | GATE umbrella issues skeleton | DONE (#207, #208 created) |

---

## GATE umbrella issues

| GATE | Issue | Children | Status |
|---|---|---|---|
| Landing Zone Done | [#207](https://github.com/100rd/platform-design/issues/207) | #156-167, #168-169, #173 | 12/15 done |
| CI/CD Hardened | [#208](https://github.com/100rd/platform-design/issues/208) | #172, #173, #177, #180, #187 | 2/5 done |

Add new GATE umbrellas in pull-requests when initiating any multi-issue effort that spans more than 3 children.

---

## Cross-cutting decisions

ADRs live in `docs/adrs/`. The two filed at the time of writing:
- [ADR-0001 OU split](docs/adrs/0001-ou-split.md) — explains why `Prod` / `NonProd` aliases were preserved instead of renaming to canonical `Production` / `Non-Production`.
- [ADR-0002 TF-only state backend bootstrap](docs/adrs/0002-tf-only-state-backend.md) — bootstrap chicken-and-egg resolution.

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
