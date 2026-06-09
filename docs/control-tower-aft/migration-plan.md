# Control Tower + AFT — phased migration plan

> **Status:** planning-only. This is the phased rollout that delivers
> [ADR-0035](../adrs/0035-control-tower-and-aft.md) (adopt AWS Control Tower as
> the landing-zone foundation, then layer AFT for vending) and the target design
> in [`../account-vending.md`](../account-vending.md). **No `terraform apply` /
> Control Tower setup happens until the future blast-radius/apply gate approves
> it** (see Dependencies on each phase). We are migrating a **live,
> already-populated** raw-Organizations estate, not greenfield.

## Companion documents

| Doc | Role |
|---|---|
| [ADR-0035](../adrs/0035-control-tower-and-aft.md) | The decision + the Control-Tower-is-a-hard-prerequisite finding |
| [`../account-vending.md`](../account-vending.md) | The target vending design this plan builds toward |
| [`ct-enrollment-runbook.md`](ct-enrollment-runbook.md) | Per-account enrollment procedure, order, and rollback (drives Phase 2) |
| [`conflict-analysis.md`](conflict-analysis.md) | The six governance conflicts (OU model, SCP slots, Identity Center, delegated-admin, CloudTrail/Config, state↔drift) and their resolution directions |
| [`risk-register.md`](risk-register.md) | Ranked risks + mitigations across all phases |

## Guiding principles

- **Non-prod first, prod last.** Every phase that touches accounts proves itself
  on `dev`/`staging` before `prod`/`dr` (enrollment order in
  [`ct-enrollment-runbook.md` §2](ct-enrollment-runbook.md)).
- **Pre-clean before enrollment.** The governance conflicts in
  [`conflict-analysis.md`](conflict-analysis.md) (especially SCP slots and
  CloudTrail/Config) are resolved *before* an account is enrolled, not after.
- **Raw-org stays authoritative until Phase 6.** Control Tower can be stood up
  and validated without decommissioning the hand-rolled vending path; cutover is
  an explicit, gated, final phase.
- **Each phase is independently revertible.** Rollback is defined per phase.

## Phase overview

| Phase | Goal | Gate to start |
|---|---|---|
| 0 | Pre-reqs: ratify home region, account/email plan, freeze policy, conflict pre-clean plan | design merged |
| 1 | Stand up the Control Tower landing zone | **apply gate** |
| 2 | Enrol the existing accounts (non-prod → prod) | Phase 1 exit + **apply gate per prod account** |
| 3 | Deploy the AFT framework module + create the four `aft-*` repos | Phase 2 exit |
| 4 | Author global + account customizations | Phase 3 exit |
| 5 | Vend a throwaway **test** account end-to-end through AFT | Phase 4 exit + **apply gate** |
| 6 | Cutover: make AFT the sole vending path; decommission raw-org vending | Phase 5 exit + **apply gate** + sign-off |

---

## Phase 0 — Pre-requisites and decisions (no apply)

**Goal:** lock every decision that is effectively permanent or that gates a later
phase, and stage the conflict pre-clean — all on paper, before any AWS change.

**Work:**
- Ratify the **home region** (`eu-west-1`) and the explicit list of CT-governed
  regions. (Home region is effectively permanent — ADR-0035 risk.)
- Confirm the **two new shared accounts**: the Control Tower **Audit** account and
  the separate **AFT management** account (in the `Deployments` OU). Decide
  whether CT's Audit/Log-Archive reuse the existing `security`/`log-archive`
  accounts or are net-new, per
  [`conflict-analysis.md` §4–§5](conflict-analysis.md). Reserve root emails.
- Produce the **conflict pre-clean plan**: for each of the six conflicts in
  [`conflict-analysis.md`](conflict-analysis.md), the concrete pre-enrollment
  action (e.g. which Config/CloudTrail resources are deleted vs retained, how the
  5/5 SCP budget is freed, how Identity Center ownership splits).
- Define the **apply-freeze policy** for an account during its enrollment window.
- Confirm service quotas allow ≥2 new accounts (CT requirement).

**Dependencies:** the design epic (this plan + ADR-0035 +
[`../account-vending.md`](../account-vending.md)) merged. The
[`ct-enrollment-runbook.md`](ct-enrollment-runbook.md),
[`conflict-analysis.md`](conflict-analysis.md), and
[`risk-register.md`](risk-register.md) authored.

**Exit criteria:**
- Home region + governed regions ratified (human sign-off).
- Audit + AFT-management account plan (reuse-vs-new) decided and emails reserved.
- Conflict pre-clean plan reviewed and accepted by platform + security owners.
- Apply-freeze policy documented.

**Artifacts/PRs:** a Phase-0 decisions doc (or an update to the risk register)
recording the home region, account plan, and pre-clean plan. **No IaC.**

**Rollback:** n/a (decisions only).

---

## Phase 1 — Stand up the Control Tower landing zone

**Goal:** a working Control Tower landing zone in the management (root) account,
with Control Tower's governance structure created *alongside* the existing
raw-Organizations structure (CT sets up a **parallel** structure — it does not
mutate existing OUs/accounts).

**Work:**
- Set up the landing zone from the management account in the ratified home region
  (managed via the landing-zone API / `aws_controltower_*`).
- Stand up the CT **Audit** and **Log Archive** accounts per the Phase-0 decision
  (reuse `security`/`log-archive` or net-new).
- Establish the Control-Tower-governed OUs that the existing accounts will map
  onto, per [`conflict-analysis.md` §1](conflict-analysis.md) (OU model
  resolution direction).
- **Do not enrol existing accounts yet** — that is Phase 2.

**Dependencies:** Phase 0 exit. **Blast-radius/apply gate approval** (first AWS
change). Home region ratified.

**Exit criteria:**
- Landing zone reports healthy; home region set.
- CT Audit + Log Archive accounts exist and pass CT health checks.
- Target governed OUs exist and the OU-mapping table (raw OU → CT OU) is
  finalised against [`conflict-analysis.md` §1](conflict-analysis.md).
- No change to existing member accounts yet (verified).

**Artifacts/PRs:** the Control Tower landing-zone IaC surface (management
account); the finalised OU-mapping table.

**Rollback:** decommission the landing zone (the raw-org structure is untouched
and remains authoritative; existing accounts were not enrolled).

---

## Phase 2 — Enrol the existing accounts

**Goal:** bring the nine canonical accounts under Control Tower governance,
**non-prod first**, after the per-account pre-clean — without disrupting live
workloads. This phase is driven end-to-end by
[`ct-enrollment-runbook.md`](ct-enrollment-runbook.md).

**Work (per account, in the runbook's order —
[`ct-enrollment-runbook.md` §2](ct-enrollment-runbook.md)):**
- **Pre-clean the conflicts** for that account
  ([`ct-enrollment-runbook.md` §1 pre-flight](ct-enrollment-runbook.md) +
  [`conflict-analysis.md`](conflict-analysis.md)): delete pre-existing AWS Config
  resources where CT requires it (Config/CloudTrail conflict, §5), reconcile SCP
  slots so CT's managed SCPs + custom SCPs stay ≤5/OU (§2), and split Identity
  Center ownership (§3) and delegated-admin (§4).
- **Freeze applies** on the account for its enrollment window.
- Ensure the `AWSControlTowerExecution` role is present (Register-OU path adds it;
  or use Landing Zone 3.1+ **automatic enrollment**).
- **Enrol** the account into its governed OU
  ([`ct-enrollment-runbook.md` §3.2](ct-enrollment-runbook.md)); CT baselines it.
- **Verify** ([`ct-enrollment-runbook.md` §3.3](ct-enrollment-runbook.md)) and
  unfreeze.

**Order:** `dev` → `staging` → (validate) → `shared`/`network` → `security`/
`log-archive` reconciliation → `prod` → `dr`, exactly as
[`ct-enrollment-runbook.md` §2](ct-enrollment-runbook.md) specifies. Each prod-tier
account is its own gated step.

**Dependencies:** Phase 1 exit. The conflict pre-clean plan (Phase 0) executed
per account. **Apply-gate approval for each prod-tier account.** Apply-freeze in
effect during each window.

**Exit criteria:**
- All nine accounts **enrolled** (not merely org members) and in the correct
  governed OU.
- Config/CloudTrail conflict resolved with no audit-trail gap
  ([`conflict-analysis.md` §5](conflict-analysis.md)).
- No OU exceeds the 5-SCP cap after CT managed SCPs are attached
  ([`conflict-analysis.md` §2](conflict-analysis.md)).
- Identity Center assignments still resolve (the `sso` module still owns
  permission sets/assignments; CT owns only enrolment —
  [`conflict-analysis.md` §3](conflict-analysis.md)).
- Per-account rollback was exercised at least once in non-prod
  ([`ct-enrollment-runbook.md` §3.4 / §5](ct-enrollment-runbook.md)).

**Artifacts/PRs:** per-account enrollment changes; the Terraform/Terragrunt
reconciliation from [`ct-enrollment-runbook.md` §4](ct-enrollment-runbook.md)
(e.g. `state mv`/`removed` blocks where CT now owns a control).

**Rollback:** per-account un-enroll back to the raw-org OU
([`ct-enrollment-runbook.md` §3.4](ct-enrollment-runbook.md)); the raw-org
structure remains authoritative throughout this phase.

---

## Phase 3 — Deploy the AFT framework + the four repos

**Goal:** a working AFT control plane wired to Control Tower, ready to vend —
but not yet owning any real account.

**Work:**
- Provision the **AFT management account** (separate from the CT management
  account) in the `Deployments` OU, if not already created in Phase 0/1.
- Deploy the **AFT framework module**
  (`aws-ia/terraform-aws-control_tower_account_factory`) **from the home region**
  (AFT deployment region must equal the CT home region), invoked with
  administrator credentials in the CT management account per AWS guidance.
- Create the four repos and seed them from the module's upstream templates:
  `aft-account-request`, `aft-global-customizations`,
  `aft-account-customizations`, `aft-account-provisioning-customizations`.
- Pin the AFT module to a specific released version (no `main`).

**Dependencies:** Phase 2 exit (CT must be healthy with enrolled accounts — AFT
requires a functioning landing zone). AFT management account available.

**Exit criteria:**
- AFT pipeline infrastructure (CodePipeline/CodeBuild/Step Functions/DynamoDB/
  Lambda) is deployed and healthy in the AFT management account.
- All four `aft-*` repos exist, are version-pinned, and their initial pipelines
  run green with empty/baseline content.
- AFT can reach the Control Tower Account Factory (connectivity/permissions
  validated) — proven for real in Phase 5.

**Artifacts/PRs:** the AFT framework module invocation (AFT management account);
the four new repos with seeded scaffolding; module version pin.

**Rollback:** destroy the AFT framework deployment and archive the four repos;
Control Tower (Phase 1–2) is unaffected.

---

## Phase 4 — Author customizations

**Goal:** encode the org-wide and per-account baselines so a vended account comes
out governed and configured, per [`../account-vending.md`](../account-vending.md)
("The two customization layers").

**Work:**
- **Global** (`aft-global-customizations`): the universal account baseline — the
  ADR-0017 items 1–4 touchpoints (RCP attachment, EC2 Declarative Policy posture,
  account IAM baseline), break-glass model
  ([ADR-0011](../adrs/0011-break-glass-iam-destroy-protection.md)), and the
  tagging taxonomy
  ([ADR-0028](../adrs/0028-unified-platform-tagging-and-labeling-taxonomy.md)).
- **Account** (`aft-account-customizations`): the per-archetype profiles
  (`workload`, `network`, `shared`, `security`, `sandbox`) from
  [`../account-vending.md`](../account-vending.md). Decide, per
  [`ct-enrollment-runbook.md` §4](ct-enrollment-runbook.md), how much existing
  per-account Terragrunt moves into AFT customizations vs stays in the account's
  Terragrunt units.
- **Provisioning** (`aft-account-provisioning-customizations`): any during-
  provisioning hooks (waits, lookups, notifications).

**Dependencies:** Phase 3 exit (the repos + pipeline must exist).

**Exit criteria:**
- `aft-global-customizations` validated (plan-green) and reviewed.
- At least the `sandbox` and one `workload` profile exist in
  `aft-account-customizations` (the profiles Phase 5 will exercise).
- Provisioning-customizations pipeline runs green.

**Artifacts/PRs:** PRs into the three customization repos.

**Rollback:** revert customization PRs; the AFT framework stays up with
empty/baseline customizations.

---

## Phase 5 — Vend a test account end-to-end

**Goal:** prove the whole vending path on a **throwaway test account** — request
→ AFT pipeline → CT Account Factory → provisioning hooks → global + account
customizations — before any real account is vended through AFT.

**Work:**
- Open a PR in `aft-account-request` for a disposable `sandbox`-profile test
  account (unique root email, `Sandbox` OU, minimal SSO access).
- Merge; watch the AFT pipeline drive Control Tower's Account Factory; confirm
  the provisioning hooks and both customization layers apply.
- Verify the account is enrolled, in the right OU, baselined, correctly tagged,
  and has the expected SSO assignments and customizations.
- **Tear the test account down** through the offboarding path in
  [`../account-vending.md`](../account-vending.md) (remove request → `Suspended`
  → drain → unenroll/close) — this also exercises offboarding once.

**Dependencies:** Phase 4 exit. **Blast-radius/apply-gate approval** (this
creates a real account). A reserved test root email.

**Exit criteria:**
- Test account vended successfully through AFT with both customization layers
  applied and verified.
- Offboarding path exercised end-to-end on the test account.
- Vend + offboard runbooks confirmed accurate (any corrections folded back into
  [`../account-vending.md`](../account-vending.md)).

**Artifacts/PRs:** the test-account request PR (and its removal PR); any doc
corrections.

**Rollback:** offboard/close the test account (which is the success path anyway).

---

## Phase 6 — Cutover and decommission raw-org vending

**Goal:** make AFT the **sole** account-vending path and retire the hand-rolled
raw-Organizations vending pieces — the final, gated step.

**Work:**
- Make `aft-account-request` the **only** sanctioned way to create an account;
  update contributor docs and `docs/ou-structure.md`'s "Adding a new account"
  guidance to point at AFT.
- Decommission the raw-org **vending** path: stop creating accounts via
  `aws_organizations_account` `for_each` over `member_accounts` in
  `terragrunt/_org/account.hcl`. Reconcile Terraform state so existing accounts
  are no longer managed by the old creation path (`removed`/`moved` blocks per
  [`ct-enrollment-runbook.md` §4](ct-enrollment-runbook.md) and
  [`conflict-analysis.md` §7](conflict-analysis.md) state↔drift).
- Keep the `organization` module's **OU + SCP/RCP** management as appropriate
  (Control Tower owns managed controls; custom SCPs/RCPs that CT does not provide
  stay in-repo) — cutover is about *vending*, not about abandoning custom
  guardrails.
- Confirm the `Suspended`-OU offboarding pattern still holds under CT governance.

**Dependencies:** Phase 5 exit (vending + offboarding proven). **Apply-gate
approval** + explicit platform/security **sign-off** (this changes how prod
accounts come into existence).

**Exit criteria:**
- AFT is the sole vending mechanism; the raw-org account-creation path is
  removed/disabled and documented as deprecated.
- Terraform state has no orphaned/duplicated ownership of enrolled accounts
  ([`conflict-analysis.md` §7](conflict-analysis.md)).
- ROADMAP `#168` flipped to DONE by the Lead; ADR-0035 `platform-design status`
  updated from `pending` toward `synced`.
- A Phase-6 review confirms either full decommission or records why any hybrid
  persists (ADR-0035 revisit trigger).

**Artifacts/PRs:** the cutover PR(s) removing/disabling raw-org vending + state
reconciliation; documentation updates.

**Rollback:** because raw-org vending is only *removed* here (and was authoritative
through Phase 5), rollback is reverting the cutover PR to re-enable the old path
while AFT is paused — though by this point AFT is proven and rollback is a
contingency, not an expectation.

---

## Dependency graph (phase-level)

```
Phase 0 (decisions)
   │
   ▼  [apply gate]
Phase 1 (stand up Control Tower)
   │
   ▼  [apply gate per prod account] + conflict pre-clean
Phase 2 (enrol existing accounts: dev→staging→…→prod→dr)
   │
   ▼
Phase 3 (AFT framework + 4 repos)
   │
   ▼
Phase 4 (global + account customizations)
   │
   ▼  [apply gate]
Phase 5 (vend + offboard a test account)
   │
   ▼  [apply gate] + sign-off
Phase 6 (cutover; decommission raw-org vending)
```

## Cross-references

- [ADR-0035](../adrs/0035-control-tower-and-aft.md) — decision + CT-prerequisite.
- [`../account-vending.md`](../account-vending.md) — target vending design.
- [`ct-enrollment-runbook.md`](ct-enrollment-runbook.md) — Phase 2 driver.
- [`conflict-analysis.md`](conflict-analysis.md) — the six conflicts pre-cleaned
  across Phases 0/2/6.
- [`risk-register.md`](risk-register.md) — ranked risks + mitigations.
- AWS: enroll existing accounts / extend governance —
  <https://docs.aws.amazon.com/controltower/latest/userguide/about-extending-governance.html>;
  AFT getting started (CT prerequisite) —
  <https://docs.aws.amazon.com/controltower/latest/userguide/aft-getting-started.html>.
