# ADR-0035: AWS Control Tower as the landing-zone foundation + AFT for account vending

- Status: **Accepted** — supersedes the AFT-vending decision item in ADR-0017.
- platform-design status: **pending** — no `aws_controltower_*` resources, no AFT
  framework module, and none of the four `aft-*` repos exist in this repo yet.
- Date: 2026-06-09
- Authors: platform-team, security
- Related issues: #168 (this epic), #157 (account structure), #158 (OU split),
  #166 (SCPs / data perimeter), #162 (config-org), #163/#164 (GuardDuty /
  SecurityHub delegations)
- Supersedes: ADR-0017 **decision item 0** (the standalone "AFT as the
  account-vending mechanism" choice) — see "Relationship to ADR-0017" below.
- Superseded by: (none)

## Context

The platform-design org is, today, a **raw AWS Organizations** estate, not an
AWS Control Tower landing zone:

- `terraform/modules/organization/main.tf` creates the org with a bare
  `aws_organizations_organization` (`feature_set = "ALL"`), hand-rolls every OU
  as `aws_organizations_organizational_unit` resources (`Security`,
  `Infrastructure`, `Workloads` + nested `NonProd`/`Prod`, `Deployments`,
  `Sandbox`, `Suspended`, `Policy-Staging`), and `for_each`-creates member
  accounts from the `member_accounts` map sourced from
  `terragrunt/_org/account.hcl`.
- There are **no `aws_controltower_*` resources anywhere** in the repo. The
  references to "Control Tower" in `terragrunt/README.md` and the SCP comments
  describe the *intended* account topology, not a deployed landing zone.
- The canonical account set is the nine accounts in `terragrunt/README.md`
  (`management`/root, `security`, `log-archive`, `network`, `shared`, `dev`,
  `staging`, `prod`, `dr`, `third-party`), governed by the OU split in
  [ADR-0001](0001-ou-split.md) and `docs/ou-structure.md`. The `Deployments` OU
  is explicitly reserved "filled when AFT lands — #168".
- Org guardrails are already live and hand-managed: 5/5 SCP slots
  (`terraform/modules/scps/main.tf`), the `Suspended` OU + `DenyAllSuspended`
  SCP with an `OrganizationAccountAccessRole` carve-out, IAM Identity Center
  permission sets (`terraform/modules/sso/`), and the
  org-delegated-admin set-ups for AWS Config (#162), GuardDuty (#163), and
  SecurityHub (#164).

ADR-0017 already decided (item 0) to vend accounts with **Account Factory for
Terraform (AFT)** because the estate is Terraform/Terragrunt-first. What ADR-0017
**did not surface** is the binding architectural constraint underneath that
choice: **AFT is not a standalone product. AFT requires a fully-deployed AWS
Control Tower landing zone as a hard prerequisite** — per AWS's own AFT
getting-started guidance, *"Before you can set up AFT, you must have an existing
AWS Control Tower landing zone."* AFT's account-creation path is literally the
Control Tower **Account Factory** wrapped in a Terraform/CodePipeline control
loop; with no Control Tower, there is no Account Factory for AFT to drive.

Therefore the decision in ADR-0017 to "stand up AFT" silently entails a much
larger, higher-risk piece of work that deserves its own ADR and its own epic:
**adopting Control Tower as the landing-zone foundation and enrolling a live,
already-populated raw-Organizations estate into it.**

## Decision

**Adopt AWS Control Tower as the landing-zone foundation for the platform-design
org, and layer Account Factory for Terraform (AFT) on top of it as the
account-vending mechanism.**

Concretely:

1. Stand up an AWS Control Tower **landing zone** from the existing management
   (root) account, choosing a single home region aligned with the estate's
   `eu-west-1` primary (Control Tower governs additional regions explicitly).
2. **Enrol the existing raw-Organizations estate** into Control Tower via the
   "extend governance to an existing organization" / Register-OU path, mapping
   the current accounts onto Control-Tower-governed OUs **without** re-creating
   them. Control Tower's `Security` OU (Log Archive + Audit) is reconciled with
   the repo's existing `security` and `log-archive` accounts.
3. Deploy the AWS-maintained **AFT framework module**
   (`aws-ia/terraform-aws-control_tower_account_factory`, a.k.a. the
   `aws-ia/control_tower_account_factory/aws` registry module) into a dedicated
   **AFT management account** (separate from the Control Tower management
   account), executed from the home region.
4. Drive AFT with its **four GitOps repos**: `aft-account-request`,
   `aft-global-customizations`, `aft-account-customizations`, and
   `aft-account-provisioning-customizations`.

**Control Tower is recorded here as a HARD PREREQUISITE of AFT** — this is the
key finding of this ADR and the reason it exists. The phased migration is
specified in [`../control-tower-aft/migration-plan.md`](../control-tower-aft/migration-plan.md);
the target vending design is in [`../account-vending.md`](../account-vending.md).

A reviewer can check conformance by confirming: (a) a Control Tower landing zone
exists and the nine canonical accounts are *enrolled* (not just org members);
(b) an AFT management account exists distinct from the CT management account;
(c) the AFT framework module is deployed from the home region; and (d) the four
`aft-*` repos exist and the `aft-account-request` repo is the only sanctioned
path to create a new account.

## Relationship to ADR-0017

[ADR-0017](0017-resource-side-perimeter-and-declarative-org-controls.md) bundled
five org-control primitives, of which **decision item 0** was "AFT as the
account-vending mechanism". That sub-decision is **SUPERSEDED by this ADR
(ADR-0035)**, which promotes account vending to a first-class epic and records
the Control-Tower prerequisite that ADR-0017 omitted.

- The *direction* is unchanged: AFT (Terraform-first) over AFC (CloudFormation
  blueprints). ADR-0035 keeps that choice and keeps the AFC rejection.
- ADR-0017's **items 1–4 are untouched** and remain valid: RCPs, EC2 Declarative
  Policies, full-IAM-language SCPs, and the Access-Analyzer custom-check CI gate.
  Those land as AFT **global customizations** once this ADR's foundation is in
  place — i.e. ADR-0035 is the substrate ADR-0017's items 1–4 ride on.
- Note: ADR-0017 names the fourth repo `aft-provisioning-customizations`; the
  correct AWS repository name is **`aft-account-provisioning-customizations`**.
  ADR-0035 uses the correct name. (ADR-0017 is left unedited per the "never
  rewrite a ratified ADR" convention; this note is the correction of record.)

Per repo convention the ADR-0017 file is **not edited**; it keeps its number and
this supersession is recorded forward from here and in `docs/adrs/README.md`.

## Alternatives considered

### Alternative A: Status quo — keep the hand-rolled raw Organizations
Continue creating accounts with `aws_organizations_account` `for_each` over the
`member_accounts` map and managing OUs/SCPs by hand.
Rejected because: it cannot deliver AFT (the ratified ADR-0017 vending decision)
at all — AFT requires Control Tower. It also leaves account *baselining*
(CloudTrail, Config, guardrail drift-detection, Identity Center enrolment) as
bespoke per-account Terraform with no managed control plane, which is exactly the
toil Control Tower's Account Factory exists to remove.

### Alternative B: Script-based declarative vending (no Control Tower, no AFT)
Build a thin in-repo vending layer: a declarative account manifest (YAML/HCL)
plus a Terragrunt/Go controller that creates accounts via the Organizations API,
moves them to the right OU, and applies a baseline stack — a "poor-man's Account
Factory" that avoids Control Tower entirely.
Rejected because: **the platform owner explicitly chose real AFT over a
script-based vending shim.** Even setting that decision aside, this re-implements
Control Tower's baselining, drift remediation, and guardrail model as
unsupported bespoke code; it diverges from AWS's managed landing-zone roadmap
(no Landing Zone version upgrades, no managed controls catalog, no auto-enroll),
and it still would not satisfy ADR-0017, which named AFT specifically. The
maintenance burden of a home-grown account factory is precisely the war story
this team avoids.

### Alternative C: AFC (Account Factory for Customizations) on Control Tower
Adopt Control Tower but vend/customize via AFC's Service-Catalog /
CloudFormation blueprints instead of AFT.
Rejected because: identical to ADR-0017's Alternative 0 — the estate is
Terraform/Terragrunt-first, and AFC grafts a parallel CloudFormation-blueprint
surface (separate language, review flow, and state model) onto an
otherwise-Terraform platform. Carried forward unchanged from ADR-0017.

### Alternative D: Control Tower landing zone WITHOUT AFT
Stand up Control Tower and vend accounts through the **console Account Factory**
(or the Service Catalog product) by hand, skipping AFT.
Rejected because: it reintroduces click-ops for the single highest-blast-radius
operation (creating an account) and gives up the GitOps request/review trail.
AFT keeps account creation as a reviewed PR in `aft-account-request`, consistent
with how every other change in this estate ships. We pay the Control Tower cost
regardless; AFT is the small marginal increment that makes vending IaC-native.

## Consequences

### Positive
- Unblocks ADR-0017's ratified AFT vending decision (and, transitively, items
  1–4 of ADR-0017, which deploy as AFT global customizations).
- Replaces bespoke per-account baselining with Control Tower's managed control
  plane (managed guardrails/controls, drift detection, Landing Zone version
  upgrades, Identity Center enrolment).
- Account creation becomes a reviewed GitOps PR in `aft-account-request` — the
  same review surface as the rest of the platform — with global + per-account
  customization layers (see [`../account-vending.md`](../account-vending.md)).
- The reserved `Deployments` OU finally has a tenant (the AFT management account
  + pipeline), as anticipated by [ADR-0001](0001-ou-split.md) and
  `docs/ou-structure.md`.

### Negative
- **We are migrating a live, already-populated organization**, not greenfield.
  Control Tower stands up a *parallel* governance structure at the Organizations
  level and enrolls existing accounts into it; reconciling that with hand-rolled
  OUs, 5/5 SCPs, and existing delegated-admin set-ups is the hard part.
- **Two new shared "management" accounts**: Control Tower's Audit account and
  AFT's own AFT-management account (distinct from the CT management account).
  This grows the canonical account count and the cost baseline (Control Tower +
  AFT run CodePipeline/CodeBuild/Step Functions/DynamoDB/Lambda continuously).
- A new mental model for reviewers: account lifecycle now spans the
  `aft-account-request` repo, the AFT pipeline, the Control Tower Account
  Factory, and the two customization repos.
- Some existing hand-managed controls overlap Control Tower's managed controls
  and must be deduplicated to avoid conflicting guardrails (see Risks).

### Risks
- **Existing AWS Config / CloudTrail / GuardDuty / SecurityHub collide with
  Control Tower baselining (highest risk).** Control Tower deploys its own
  CloudTrail org-trail, Config recorders/aggregator, and security baseline via
  StackSets. The repo already has config-org (#162), cloudtrail-org (#161),
  GuardDuty (#163), and SecurityHub (#164) delegated-admin set-ups live. AWS
  requires **pre-existing Config resources to be deleted before an account can
  be enrolled** as the Audit/Log Archive account. Mitigation: the migration plan
  sequences a Config/CloudTrail reconciliation (decide CT-owned vs repo-owned per
  control) *before* enrolment, and stages it in `Policy-Staging`/non-prod first.
  Detailed in [`../control-tower-aft/conflict-analysis.md`](../control-tower-aft/conflict-analysis.md).
- **SCP slot interaction.** Control Tower attaches its own managed-control SCPs
  to governed OUs, and OUs are capped at 5 SCPs. With root already at 5/5, the
  enrolment plan must verify Control Tower's managed SCPs + existing custom SCPs
  do not exceed the cap on any OU. Mitigation: tracked in the conflict analysis
  and the [`../control-tower-aft/risk-register.md`](../control-tower-aft/risk-register.md);
  RCPs (ADR-0017) relieve some pressure by moving controls off the SCP budget.
- **Identity Center ownership.** Control Tower expects to manage IAM Identity
  Center enrolment; the repo's `sso` module already manages permission sets and
  assignments. Mitigation: keep permission-set/assignment authorship in the `sso`
  module, let Control Tower own only account *enrolment* into Identity Center;
  reconcile in the enrollment runbook.
- **Enrolment is not free of disruption.** Baselining an existing account
  deploys StackSets and can briefly contend with in-flight Terraform applies.
  Mitigation: enrol non-prod first, freeze applies on an account during its
  enrolment window, and gate prod enrolment behind the future blast-radius/apply
  gate.
- **Home-region lock-in.** Control Tower's home region and AFT's deployment
  region must match and are effectively permanent. Mitigation: ratify the home
  region (`eu-west-1`) explicitly in Phase 0 before any apply.

## Revisit trigger

Re-open this decision if any of the following hold:

- **AWS removes the Control-Tower-as-prerequisite constraint** — e.g. AFT (or a
  successor) becomes deployable against a raw Organizations estate, or AWS ships
  a Terraform-native landing zone that does not require Control Tower. The whole
  cost/benefit of Alternatives A/B changes if the prerequisite disappears.
  (Re-verified 2026-06-09: still a prerequisite — see "Re-verified current as of
  2026-06-09" below.)
- **The Config/CloudTrail/SecurityHub conflict proves unresolvable in non-prod**
  (Phase 2 exit criteria cannot be met without destructive changes to live audit
  infrastructure) — fall back to re-evaluating Alternative B (scripted vending)
  or deferring the epic.
- **Control Tower's managed SCPs cannot coexist with the custom SCPs under the
  5-per-OU cap** even after RCP relief (ADR-0017) — revisit the OU topology
  (ADR-0001) or the control split before proceeding past Phase 2.
- **The estate's home-region assumption changes** (e.g. a move off `eu-west-1`
  primary) before Phase 1 — Control Tower's home region is effectively permanent,
  so this must be settled before any landing-zone apply.
- A scheduled review at **Phase 6 cutover**: confirm the raw-Organizations
  vending path is fully decommissioned and AFT is the sole vending mechanism, or
  record why a hybrid persists.

## Implementation notes

- This ADR is **planning-only**. No `aws_controltower_*` resources, no AFT module
  invocation, and no `aft-*` repos are created by the PR that introduces this
  ADR. Implementation is gated behind the future blast-radius/apply gate.
- New modules / surfaces this decision will eventually add (not in this PR):
  - a Control Tower landing-zone surface (managed via `aws_controltower_*` /
    the landing-zone API) under the management account,
  - an AFT framework module invocation in a new **AFT management account**,
  - four new repos: `aft-account-request`, `aft-global-customizations`,
    `aft-account-customizations`, `aft-account-provisioning-customizations`.
- **AFT module version + provider pins** (re-verified 2026-06-09): pin the AFT
  framework module to **`?ref=1.20.1`** (latest, no `main`). AFT 1.20.1 requires
  `aws >= 6.0.0, < 7.0.0` and Terraform `>= 1.6.1, < 2.0.0`; this repo's
  `aws ~> 6.0` and Terraform `1.14.8` satisfy both. Detail in "Re-verified current
  as of 2026-06-09" below.
- Phasing, dependencies, and exit criteria: see
  [`../control-tower-aft/migration-plan.md`](../control-tower-aft/migration-plan.md).
  Target vending design: see [`../account-vending.md`](../account-vending.md).
  Conflict analysis and risk register (teammate-authored):
  [`../control-tower-aft/conflict-analysis.md`](../control-tower-aft/conflict-analysis.md),
  [`../control-tower-aft/risk-register.md`](../control-tower-aft/risk-register.md).
- Enrolment runbook (teammate-authored):
  [`../control-tower-aft/ct-enrollment-runbook.md`](../control-tower-aft/ct-enrollment-runbook.md).
- Rollback: each phase is independently revertible (see the migration plan). The
  raw-Organizations modules remain authoritative until Phase 6 cutover; Control
  Tower can be set up and enrolment validated in non-prod without touching prod.
- Effort: **L** (live-org migration). Tracked by epic #168.

## References

- AFT requires an existing Control Tower landing zone (the prerequisite):
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html>
- AFT overview / architecture:
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html>,
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-architecture.html>
- AFT framework module (`aws-ia/terraform-aws-control_tower_account_factory`):
  <https://github.com/aws-ia/terraform-aws-control_tower_account_factory>,
  <https://registry.terraform.io/modules/aws-ia/control_tower_account_factory/aws/latest>
- Extend governance to an existing organization / enroll existing accounts:
  <https://docs.aws.amazon.com/controltower/latest/userguide/about-extending-governance.html>,
  <https://docs.aws.amazon.com/controltower/latest/userguide/enroll-account.html>
- Control Tower automatic enrollment (Landing Zone 3.1+, 2025-11):
  <https://aws.amazon.com/about-aws/whats-new/2025/11/aws-control-tower-automatic-enrollment/>
- Related ADRs: [ADR-0001](0001-ou-split.md) (OU split),
  [ADR-0017](0017-resource-side-perimeter-and-declarative-org-controls.md)
  (declarative org controls; AFT item superseded here).

## Re-verified current as of 2026-06-09

A fresh check of the AFT module and AWS Control Tower docs (current 2026-06-09)
against this ADR. **The load-bearing thesis is unchanged: a deployed AWS Control
Tower landing zone is still a HARD PREREQUISITE of AFT** — AWS: *"Before you can
set up AFT, you must have an existing AWS Control Tower landing zone,"* and the
AFT management account is created while signed into the **CT** management account.
Nothing below changes the decision; the new facts are folded in as currency.

**AFT module + toolchain (ground-truth from the registry/GitHub release APIs, not
cached search snippets):**

| Item | Value (2026-06-09) | Source |
|---|---|---|
| AFT module latest | **1.20.1** (released 2026-05-20; 72 versions total) | GitHub releases / Terraform Registry |
| AFT `aws` provider requirement | **`>= 6.0.0, < 7.0.0`** | module `versions.tf` (`main`) |
| AFT Terraform requirement | **`>= 1.6.1, < 2.0.0`** (floor raised to 1.6.1 for the HashiCorp provider-signing GPG-key rotation) | module `versions.tf` (`main`) |
| This repo's `aws` provider pin | **`~> 6.0`** (every org module + `terragrunt/versions.hcl`) | repo |
| This repo's Terraform pin | **1.14.8** | `.tool-versions`, `terragrunt/versions.hcl` |

→ **Compatibility holds.** `aws ~> 6.0` is a subset of AFT's `>= 6.0.0, < 7.0.0`,
and Terraform 1.14.8 is well above AFT's 1.6.1 floor. Pin the AFT module to
**`?ref=1.20.1`** (no `main`) when Phase 3 lands. Other 1.20.x additions (optional
KMS encryption for AFT's CloudWatch log groups / SNS topics; OIDC for TFE/HCP
workspaces; removal of the ScanProvisionedProducts pre-check) do not affect this
design.

**Confirmed unchanged:**

- **CT-is-a-prerequisite** — still true for AFT 1.x (see above). The "Revisit
  trigger" for this constraint disappearing remains hypothetical.
- **The four-repo model** — `aft-account-request`, `aft-global-customizations`,
  `aft-account-customizations`, `aft-account-provisioning-customizations` — is
  current and exactly as documented here (including the corrected 4th-repo name).
- **Enroll-existing-org / Register-OU** path still exists and still applies.
- Control Tower landing zone is on the **3.x** line (current 3.3 / baseline 4.0);
  the single-home-region + explicitly-governed-additional-regions model stands.

**New since the design was written (folded in, non-material to the decision):**

- **Automatic enrollment is GA** (Landing Zone **3.1+**, announced 2025-11). It
  lets an account be enrolled by **moving it into a governed OU via the
  Organizations API/console** — CT then applies that OU's baseline + controls with
  no separate per-account "Enroll" step. It is opt-in (`RemediationType =
  Inheritance Drift` on Create/UpdateLandingZone), requires the
  `AWSControlTowerExecution` role on the target account (a prereq we already
  carry), and does **not** retroactively fix accounts moved before it was enabled.
  This streamlines the **mechanism** of Phase 2 enrollment in the migration plan
  but does **not** remove any of the six pre-enrollment conflicts in
  [`../control-tower-aft/conflict-analysis.md`](../control-tower-aft/conflict-analysis.md):
  moving an account in still triggers CT's managed-SCP attach (the 5/5-slot
  hard-stop), Config-recorder creation (the recorder collision), and the
  delegated-admin / Identity-Center hand-offs. The pre-clean still gates Phase 2.

**Sources for this re-verification:**

- AFT prerequisite + management-account creation:
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html>,
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-resources.html>
- AFT module releases (1.20.1) + provider/TF requirements:
  <https://github.com/aws-ia/terraform-aws-control_tower_account_factory/releases>,
  <https://registry.terraform.io/modules/aws-ia/control_tower_account_factory/aws/latest>
- Automatic enrollment (GA, LZ 3.1+) — move-into-OU mechanism + prerequisites:
  <https://docs.aws.amazon.com/controltower/latest/userguide/account-auto-enrollment.html>,
  <https://docs.aws.amazon.com/controltower/latest/userguide/configure-auto-enroll.html>,
  <https://aws.amazon.com/about-aws/whats-new/2025/11/aws-control-tower-automatic-enrollment/>
- Landing zone versions (3.x / baseline 4.0):
  <https://docs.aws.amazon.com/controltower/latest/userguide/lz-version-selection.html>

---
*Doc-verified 2026-06-09 against official AWS Control Tower / AFT documentation.
Re-verified 2026-06-09 (the section above) — AFT 1.20.1, `aws >= 6.0, < 7.0` vs
repo `aws ~> 6.0` COMPATIBLE, CT-prerequisite confirmed. Planning-only ADR —
decided, not yet implemented in platform-design. Tracked by epic #168;
implementation gated behind the future blast-radius/apply gate.*
