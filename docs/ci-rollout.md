# CI Two-Step Rollout: Build/Test → Per-Account Apply

This document formalises the two-stage CI rollout pattern for Terragrunt
infrastructure changes in this repository.  The split is enforced by the GitHub
Actions workflow topology: **Stage 1 runs on pull requests**, **Stage 2 runs
only after a PR merges to `main`**.  The merge itself is the hard gate between
the two stages.

---

## Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│  STAGE 1 — Build / Validate / Test  (runs on every PR, blocks merge)      │
│                                                                            │
│   PR opened / updated                                                      │
│        │                                                                   │
│        ├─► terragrunt-validate.yml  ──► hclfmt check + HCL syntax lint    │
│        │        jobs: hclfmt, validate-catalog                             │
│        │                                                                   │
│        ├─► terratest.yml  ──────────► unit-tests → plan-tests             │
│        │        jobs: unit-tests, plan-tests, integration-tests (nightly) │
│        │                                                                   │
│        └─► terragrunt-plan.yml  ────► per-changed-unit plan matrix        │
│                 jobs: detect-changes, plan (matrix), plan-status           │
│                       ↳ posts plan diff comment on PR                      │
│                                                                            │
│   ✓ All three workflows must pass before merge is permitted                │
│     (branch protection required-status-checks: plan-status, hclfmt,       │
│      validate-catalog, unit-tests)                                         │
└─────────────────────────────────────────┬─────────────────────────────────┘
                                          │
                                    PR merged to main
                                   (the stage boundary)
                                          │
┌─────────────────────────────────────────▼─────────────────────────────────┐
│  STAGE 2 — Per-Account Apply  (runs only on push to main)                 │
│                                                                            │
│   push: main  (or workflow_dispatch with env + module targeting)           │
│        │                                                                   │
│        └─► terragrunt-apply.yml                                           │
│                 jobs:                                                       │
│                   detect-changes  ──► finds changed terragrunt units      │
│                        │                                                   │
│                        └─► apply (matrix, max-parallel: 1, fail-fast)     │
│                                 ├─ module contains 'prod'   → environment:│
│                                 │    production  (requires manual approval)│
│                                 ├─ module contains 'staging'→ environment:│
│                                 │    staging     (requires reviewer)       │
│                                 └─ all others   → environment:            │
│                                      development (auto-approved)           │
│                                                                            │
│   ✓ Applies are serialised: concurrency group "terragrunt-apply",         │
│     cancel-in-progress: false — no two applies ever run in parallel       │
│                                                                            │
│   ✓ Slack notifications on failure (if SLACK_WEBHOOK_URL is set)          │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Stage 1 — Build, Validate, and Test

Stage 1 is composed of three workflows that all trigger on `pull_request` events
for changes under `terragrunt/**`, `catalog/**`, or `terraform/modules/**`.

### 1a. HCL Validation — `terragrunt-validate.yml`

**Trigger:** `pull_request` (+ `push:main`, `workflow_dispatch`)

| Job | What it does |
|-----|-------------|
| `hclfmt` | Runs `terragrunt hcl format --check --diff`.  Fails if any `.hcl` file is not canonically formatted. |
| `validate-catalog` | Walks every `*.hcl` under `catalog/` and `terragrunt/`, counts `{`/`}` pairs, and fails on unbalanced braces. |

These two jobs are the fastest gate (~30 s) and catch formatting and syntax
errors before any AWS credential is needed.

### 1b. Module Tests — `terratest.yml`

**Trigger:** `pull_request` for paths `tests/terraform/**` and
`terraform/modules/{vpc,s3-app,eks}/**`; nightly schedule; `workflow_dispatch`.

| Job | What it does |
|-----|-------------|
| `unit-tests` | `go build ./...` + `go vet ./...` — compiles all Terratest code, no AWS credentials needed. |
| `plan-tests` | Runs `TestEKSPlanValidation` + `TestEKSClusterVersions` against the `terratest` GitHub environment (OIDC-scoped credentials). |
| `integration-tests` | Full `TestVPC` / `TestS3` against real AWS — runs **nightly** or on `workflow_dispatch` with `run_full_tests: true` only. Not a PR gate to avoid long-running real-infra creation on every branch push. |

> **Scope note:** `terratest.yml` gates on changes to reusable module source
> (`terraform/modules/`) and their tests.  Changes to account-level
> Terragrunt unit configs (`terragrunt/{account}/...`) do not independently
> trigger this workflow, because those units consume published module versions
> and do not change module logic.  The plan output posted by `terragrunt-plan.yml`
> (Stage 1c) is the validation signal for account-level unit changes.

### 1c. Speculative Plan — `terragrunt-plan.yml`

**Trigger:** `pull_request` for `terragrunt/**`, `catalog/**`, `terraform/modules/**`.

| Job | What it does |
|-----|-------------|
| `detect-changes` | Diffs `origin/main...HEAD` for `*.hcl`/`*.tf`/`*.tfvars`; emits the list of changed Terragrunt unit directories as a JSON matrix. |
| `plan` (matrix) | For each changed unit: OIDC auth → `terragrunt init` → `terragrunt plan -out=tfplan` → exports plan JSON → **posts/updates a plan comment on the PR** (marker `<!-- tg-plan:<module> -->`). `fail-fast: false` so all units are planned even if one fails. |
| `plan-status` | Required-status-check gate: fails if any `plan` matrix job failed. |

The plan comment includes a resource-change summary table and a destructive-change
callout (`[!WARNING]`) so reviewers can see `+add / ~change / -destroy / replace`
counts at a glance.

OIDC is optional during bootstrap: if `TERRAFORM_PLAN_ROLE_ARN` is not yet set
(i.e., the `catalog/units/github-oidc` unit has not been applied), the
credential step sets `continue-on-error: true` and a placeholder comment is
posted instead of a real plan.

---

## Stage 2 — Per-Account Apply

Stage 2 is handled entirely by `terragrunt-apply.yml`.

**Trigger:** `push:main` for `terragrunt/**`, `catalog/**`, `terraform/modules/**`;
or `workflow_dispatch` for targeted re-runs.

### Job: `detect-changes`

On `push:main` the job diffs `HEAD~1..HEAD` for `*.hcl`/`*.tf`/`*.tfvars` files
under `terragrunt/{account}/{region}/{stack}/` or `catalog/units/`.  The resulting
list of directories is the matrix input for the `apply` job.

On `workflow_dispatch` with `module_path` set, only that path is applied.  With
`environment` set but no `module_path`, all units under
`terragrunt/<environment>/` are targeted.

### Job: `apply` (matrix, `max-parallel: 1`, `fail-fast: true`)

For each changed unit the job:

1. Checks out the repository.
2. Installs Terraform `1.14.8` + Terragrunt `0.99.5`.
3. Assumes the `TERRAFORM_APPLY_ROLE_ARN` IAM role via OIDC.
4. Runs `terragrunt init --non-interactive`.
5. Runs `terragrunt plan -out=tfplan` (saved plan ensures apply is idempotent).
6. Runs `terragrunt apply -auto-approve tfplan`.
7. On failure: posts a Slack notification if `SLACK_WEBHOOK_URL` is configured.

**Environment mapping** (GitHub Environments with optional branch-protection
approval rules):

| Module path contains | GitHub Environment | Default gate |
|---------------------|--------------------|--------------|
| `prod` | `production` | Manual approval required (configure in Settings → Environments) |
| `staging` | `staging` | Reviewer required (configure in Settings → Environments) |
| anything else | `development` | Auto-approved |

**Serialisation:** the `concurrency` block sets
`group: terragrunt-apply, cancel-in-progress: false`.  This means a second apply
run queues behind the first rather than being cancelled — no two applies can run
simultaneously, preventing state-lock races across accounts.

---

## Promotion Path: dev → staging → prod

A typical change promotes through accounts as follows:

```
1. Engineer opens a PR with changes under:
      terragrunt/dev/eu-west-1/platform/
      terragrunt/staging/eu-west-1/platform/
      terragrunt/prod/eu-west-1/platform/

2. Stage 1 fires on the PR:
   - terragrunt-validate.yml: hclfmt + syntax check for all three units
   - terragrunt-plan.yml:     posts three plan comments, one per unit
   - terratest.yml:           unit/plan tests (if module source also changed)

3. PR reviewer approves based on plan output + diff.

4. PR merges to main.

5. Stage 2 fires (terragrunt-apply.yml, push:main):
   - detect-changes finds all three units in the merge commit diff
   - apply matrix runs with max-parallel: 1, so units are applied in
     alphabetical matrix order.

     dev unit     → environment: development  → auto-approved → applied
     prod unit    → environment: production   → waits for manual approval
     staging unit → environment: staging      → waits for reviewer

   Approval for staging and prod is given via the GitHub Actions
   "Review deployments" dialog on the workflow run.  Each environment's
   protection rules are configured in Settings → Environments.
```

> If you want a strict **dev-first, then staging, then prod** sequence (rather
> than parallel environment jobs each pending their own gate), split the change
> into three separate PRs or use `workflow_dispatch` with `environment` and
> `module_path` to apply each account manually in order.

---

## Targeting a Single Account or Module

### Via `workflow_dispatch`

Navigate to **Actions → Terragrunt Apply → Run workflow** and fill in:

| Input | Example | Effect |
|-------|---------|--------|
| `environment` | `dev` | (used for discovery when `module_path` is empty) |
| `module_path` | `terragrunt/prod/eu-west-1/platform` | Applies exactly this unit |

With only `environment` set and `module_path` empty, the `detect-changes` job
runs `find terragrunt/<environment>/` to enumerate all units in that account
and applies them all.

With `module_path` set, only that single unit is applied regardless of
`environment`.

### Via branch-protection skip (emergency)

For emergency single-account fixes, push to a short-lived branch, create a
targeted PR, merge it, then use `workflow_dispatch` with `module_path` to apply
only the affected unit without touching other accounts.

---

## Required Secrets and Variables

| Name | Type | Purpose |
|------|------|---------|
| `TERRAFORM_PLAN_ROLE_ARN` | repository variable | IAM role for plan OIDC auth (optional during bootstrap) |
| `TERRAFORM_APPLY_ROLE_ARN` | repository variable | IAM role for apply OIDC auth |
| `SLACK_WEBHOOK_URL` | repository secret | Slack incoming-webhook for failure/success notifications (optional) |

> No long-lived AWS keys: both plan and apply use **GitHub OIDC → IAM role
> assumption** via `aws-actions/configure-aws-credentials@v4`.

---

## Branch Protection Recommended Required-Status-Checks

To enforce Stage 1 as a hard gate before any merge, configure the following
required checks on the `main` branch:

- `Plan Status` (from `terragrunt-plan.yml`, job `plan-status`)
- `HCL Format Check` (from `terragrunt-validate.yml`, job `hclfmt`)
- `Validate Catalog Units` (from `terragrunt-validate.yml`, job `validate-catalog`)
- `Unit Tests` (from `terratest.yml`, job `unit-tests`)

---

## Pipeline Gap Assessment (Issue #187)

The two-stage pattern was already functionally present when this document was
written:

- **Stage 1** (validate + plan + terratest) runs exclusively on pull requests.
- **Stage 2** (apply) runs exclusively on `push:main` or `workflow_dispatch`.
- The apply job is further gated by GitHub Environment protection rules for
  staging and prod.
- Applies are serialised via the `terragrunt-apply` concurrency group.

**No net-new CI workflow changes were required to satisfy the acceptance
criteria.** This document is the primary deliverable: it formalises the
existing split, names each workflow and job explicitly, and provides the
promotion path and single-account targeting instructions.
