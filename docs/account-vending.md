# Account vending under AFT (target design)

> **Status:** target design — planning-only. Vending today is the hand-rolled
> raw-Organizations path (`aws_organizations_account` `for_each` over the
> `member_accounts` map in `terragrunt/_org/account.hcl`). This document
> describes where we are going once [ADR-0035](adrs/0035-control-tower-and-aft.md)
> lands AWS Control Tower + Account Factory for Terraform (AFT). The rollout that
> gets us here is [`control-tower-aft/migration-plan.md`](control-tower-aft/migration-plan.md).

## Why this exists

[ADR-0035](adrs/0035-control-tower-and-aft.md) adopts **AWS Control Tower** as the
landing-zone foundation and **AFT** as the account-vending mechanism (superseding
the AFT decision item in
[ADR-0017](adrs/0017-resource-side-perimeter-and-declarative-org-controls.md)).
The binding constraint: **AFT requires a deployed Control Tower landing zone** —
AFT's account-creation path is the Control Tower **Account Factory** wrapped in a
GitOps/Terraform control loop. This doc is the target *vending* design; the
landing-zone foundation it sits on is described in the ADR and migration plan.

## Building blocks

| Component | What it is | Where it lives |
|---|---|---|
| Control Tower landing zone | Managed governance control plane: managed controls, baselining via StackSets, Identity Center enrolment | Control Tower **management** account (the existing root account) |
| Control Tower **Account Factory** | The account-provisioning engine AFT drives | management account |
| **AFT framework** (`aws-ia/terraform-aws-control_tower_account_factory`) | Terraform module deploying the vending pipeline (CodePipeline / CodeBuild / Step Functions / DynamoDB / Lambda / SNS) | a dedicated **AFT management account** (distinct from the CT management account) in the `Deployments` OU |
| `aft-account-request` | GitOps repo of account-request Terraform — the **only** sanctioned way to ask for an account | new repo |
| `aft-global-customizations` | Terraform applied to **every** AFT-vended account (org-wide baseline) | new repo |
| `aft-account-customizations` | Terraform applied to **named** accounts/customization profiles (per-account / per-archetype) | new repo |
| `aft-account-provisioning-customizations` | Step-Functions hooks that run **during** provisioning, before customizations | new repo |

> Naming note: AWS's fourth repo is `aft-account-provisioning-customizations`.
> [ADR-0017](adrs/0017-resource-side-perimeter-and-declarative-org-controls.md)
> abbreviates it `aft-provisioning-customizations`; ADR-0035 records the correct
> name. Two distinct management accounts (CT management vs AFT management) is by
> design — do not collapse them.

## The vending flow

```
 engineer
    │  (1) opens PR adding/editing an account request (Terraform)
    ▼
┌─────────────────────┐   merge to main
│ aft-account-request │ ───────────────────────────────┐
│  repo (GitOps)      │                                 │
└─────────────────────┘                                 ▼
                                          ┌──────────────────────────────┐
                                          │ AFT pipeline (AFT mgmt acct)  │
                                          │  CodePipeline → CodeBuild →   │
                                          │  Step Functions → DynamoDB    │
                                          └──────────────┬───────────────┘
                                                         │ (2) invokes
                                                         ▼
                                          ┌──────────────────────────────┐
                                          │ Control Tower Account Factory │
                                          │  creates + baselines account, │
                                          │  places it in the target OU,  │
                                          │  enrols into Identity Center  │
                                          └──────────────┬───────────────┘
                                                         │ (3) provisioning hooks
                                                         ▼
                                   aft-account-provisioning-customizations
                                                         │
                                                         ▼ (4) customization layers
                              ┌──────────────────────────┴───────────────────────────┐
                              │ aft-global-customizations  →  aft-account-customizations │
                              │   (every account)              (this account / profile)  │
                              └──────────────────────────────────────────────────────────┘
                                                         │
                                                         ▼
                                            account ready, governed, baselined
```

1. **Request** — an engineer opens a PR in `aft-account-request` adding a Terraform
   account-request block (account name, root email, OU, SSO access, tags such as
   `Owner`/`CostCenter`/`Environment`, and a customization-profile name).
2. **Provision** — on merge, the AFT pipeline (in the AFT management account)
   picks up the request and invokes the **Control Tower Account Factory**, which
   creates the account, applies the Control Tower **baseline** (managed controls,
   CloudTrail, Config, guardrail drift detection), places it in the requested
   **OU**, and enrols it into IAM Identity Center.
3. **Provisioning hooks** — `aft-account-provisioning-customizations` runs
   Step-Functions logic *during* provisioning (e.g. wait-conditions, lookups,
   notifications) before the customization layers run.
4. **Customize** — AFT applies the **two customization layers** (below), then the
   account is ready: governed by Control Tower, baselined, and carrying both the
   org-wide and per-account Terraform.

## The two customization layers

AFT applies customizations in a fixed order — **global first, then account** —
so per-account Terraform can rely on the global baseline already existing.

### 1. Global customizations (`aft-global-customizations`)
Terraform applied to **every** AFT-vended account. This is the org-wide account
baseline and the natural home for the cross-cutting controls this estate already
cares about:

- The resource-side / declarative controls from
  [ADR-0017](adrs/0017-resource-side-perimeter-and-declarative-org-controls.md)
  items 1–4 (RCP attachment touchpoints, EC2 Declarative Policy posture,
  account-level IAM baseline) — ADR-0035 is the substrate these ride on.
- Baseline IAM (e.g. the break-glass model from
  [ADR-0011](adrs/0011-break-glass-iam-destroy-protection.md), CI/CD OIDC roles),
  the unified tagging taxonomy
  ([ADR-0028](adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)),
  and any per-account guardrail that should be universal.

### 2. Account customizations (`aft-account-customizations`)
Terraform applied to **named** accounts or **customization profiles** (archetypes).
This is where account *type* diverges. Mapping onto the canonical accounts
(`terragrunt/README.md`, `docs/ou-structure.md`):

| Profile / account | Adds on top of global |
|---|---|
| `workload` (`dev`, `staging`, `prod`, `dr`) | VPC + TGW spoke attachment, EKS prerequisites, RDS, environment-specific IAM/secrets |
| `network` | Transit Gateway hub, Route 53 resolver, inspection VPC |
| `shared` | ECR, Route 53 private zones, ACM authority |
| `security` | delegated-admin tooling reconciled with Control Tower's Audit baseline |
| `sandbox` | hard spend caps (Budgets, #175), region-restrict, no shared-services trust |

> Today the equivalent per-account configuration lives in each account's
> Terragrunt folder. The migration plan
> ([`control-tower-aft/migration-plan.md`](control-tower-aft/migration-plan.md),
> Phase 4) defines how much of that moves into `aft-account-customizations`
> versus staying in the existing Terragrunt units. AFT customizations and
> Terragrunt are not mutually exclusive — AFT bootstraps the account and applies
> the baseline; richer stacks can still be Terragrunt-managed in the account
> afterward.

## Requesting, reviewing, and vending a new account

1. **Request:** open a PR in `aft-account-request` with the account-request
   Terraform — name, unique root email, target OU, SSO group/permission-set
   access, required tags (`Owner`, `Team`, `CostCenter`, `Environment`,
   `Project`), and the customization profile.
2. **Review:** standard PR review. Reviewers check the OU is correct (blast-radius
   boundary), the root email is unique and owned, the tags satisfy the taxonomy,
   the customization profile exists, and — for any prod-tier account — that the
   future **blast-radius/apply gate** has approved (see the migration plan).
3. **Merge → vend:** merge to main triggers the AFT pipeline, which provisions and
   baselines the account through Control Tower's Account Factory and applies the
   two customization layers. Provisioning an account takes minutes-to-tens-of-
   minutes; the pipeline reports status (CodePipeline + SNS).
4. **Verify:** confirm the account is enrolled (not merely an org member), placed
   in the right OU, carries the Control Tower baseline, and has the expected
   global + account customizations and SSO assignments.

## Offboarding (decommissioning an account) in the AFT model

AFT vends accounts; it does **not** hard-delete them. Offboarding is deliberately
a guarded, mostly-manual path that reuses the existing `Suspended` OU quarantine
pattern already in the repo (`terraform/modules/organization` +
`DenyAllSuspended` SCP; `docs/ou-structure.md`):

1. **Remove the request** — delete/disable the account's block in
   `aft-account-request` so AFT stops managing/refreshing it. (Removing the
   request does not delete the AWS account — by design.)
2. **Quarantine** — move the account into the **`Suspended`** OU
   (`aws organizations move-account ...`). The `DenyAllSuspended` SCP blocks all
   actions except by `OrganizationAccountAccessRole`, which is retained for
   break-glass, log/audit retrieval, and the offboarding runbook.
3. **Drain & retain** — under `OrganizationAccountAccessRole`, export/retain logs
   and any required data before closure (the carve-out exists precisely for this).
4. **Unenroll & close** — unenroll the account from Control Tower governance, then
   close the AWS account via the Organizations console/API per AWS's account-
   closure process. Closure is a human-gated, irreversible step.

> Offboarding touches data deletion and account closure, both of which are
> **critical, human-approved actions** (see `.claude/rules/critical-decisions.md`)
> and out of scope for any automated AFT path.

## How this differs from vending today

| | Today (raw Organizations) | Target (AFT on Control Tower) |
|---|---|---|
| Create an account | `aws_organizations_account` `for_each` over `member_accounts` in `terragrunt/_org/account.hcl`, applied from management | PR in `aft-account-request` → AFT pipeline → CT Account Factory |
| Baseline | bespoke per-account Terraform / Terragrunt | Control Tower managed baseline + `aft-global-customizations` |
| Per-account config | the account's Terragrunt folder | `aft-account-customizations` (+ Terragrunt where richer) |
| OU placement | `ou` field in the `member_accounts` map | request's target OU, enforced by Control Tower |
| Guardrails | hand-managed SCPs (5/5) | Control Tower managed controls + custom SCPs/RCPs (ADR-0017) |
| Offboarding | move to `Suspended` OU manually | same `Suspended` quarantine + remove AFT request + unenroll/close |

## References

- [ADR-0035](adrs/0035-control-tower-and-aft.md) — Control Tower + AFT (this
  doc's governing ADR; CT is a hard prerequisite of AFT).
- [ADR-0017](adrs/0017-resource-side-perimeter-and-declarative-org-controls.md) —
  declarative org controls (AFT item superseded by ADR-0035; items 1–4 land as
  global customizations).
- [ADR-0001](adrs/0001-ou-split.md) / `docs/ou-structure.md` — OU split; the
  `Deployments` OU hosts the AFT management account + pipeline.
- [`control-tower-aft/migration-plan.md`](control-tower-aft/migration-plan.md) —
  the phased rollout that delivers this design.
- AFT overview / four-repo customization model:
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html>,
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-account-customization-options.html>
- Provision a new account with AFT:
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-provision-account.html>
