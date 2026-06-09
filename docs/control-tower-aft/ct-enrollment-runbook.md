# Control Tower Enrollment Runbook — Per-Account

> **Scope:** Issue #168 (Control Tower + AFT migration epic). This runbook covers
> **enrolling the existing hand-rolled AWS Organization into AWS Control Tower (CT),
> account-by-account**, after the CT landing zone has been stood up in the
> management account. It is a **planning document** — no IaC changes, no `apply`.
>
> **Ground truth (do not invent accounts):** the organization today is a raw
> `aws_organizations_organization` (`terraform/modules/organization/main.tf`) driven
> by a `member_accounts` map plus per-account `account.hcl` files under
> `terragrunt/<account>/`. Control Tower is **not deployed**. Enrolling an *existing*
> org into CT is done one account at a time once the landing zone exists.
>
> **Companion documents (authored by teammates — relative links):**
> - [migration-plan.md](./migration-plan.md) — overall CT + AFT migration phasing and landing-zone setup
> - [conflict-analysis.md](./conflict-analysis.md) — resource-level overlap between the hand-rolled org and CT-managed controls
> - [risk-register.md](./risk-register.md) — risk catalogue and mitigations
>
> This runbook assumes the landing zone (CT home region, the CT-managed
> `Security` foundational OU, log-archive + audit accounts, the CT CloudTrail and
> Config baseline) is already created per [migration-plan.md](./migration-plan.md).
> Enrollment then *folds the existing accounts in*.

---

## 1. Account inventory (authoritative — from `account.hcl`)

Eleven accounts are defined in the repo. The org-creation `member_accounts` map in
[`terragrunt/_org/account.hcl`](../../terragrunt/_org/account.hcl) lists five
(`network`, `dev`, `staging`, `prod`, `dr`); the richer, authoritative per-account
identity lives in each `terragrunt/<account>/account.hcl`. Quoted directly:

| Account | `aws_account_id` | `email` | `org_ou` | `org_account_type` |
|---|---|---|---|---|
| `management` | `000000000000` *(placeholder)* | `aws+management@example.com` | `Root` | `management` |
| `log-archive` | `888888888888` | `aws+log-archive@example.com` | `Security` | `log-archive` |
| `security` | `777777777777` | `aws+security@example.com` | `Security` | `security` |
| `third-party` | `121212121212` | `aws+third-party@example.com` | `Security` | `third-party-integrations` |
| `network` | `555555555555` | `aws+network@example.com` | `Infrastructure` | `network` |
| `shared` | `999999999999` | `aws+shared@example.com` | `Infrastructure` | `shared-services` |
| `sandbox` | `007027391583` | `gerasimowigor@gmail.com` | `Sandbox` | `workload` |
| `dev` | `111111111111` | `aws+dev@example.com` | `NonProd` | `workload` |
| `staging` | `222222222222` | `aws+staging@example.com` | `NonProd` | `workload` |
| `prod` | `333333333333` | `aws+prod@example.com` | `Prod` | `workload` |
| `dr` | `444444444444` *(see ⚠️)* | `aws+dr@example.com` | `Prod` | `workload` |

OU hierarchy is the canonical 8-OU split from
[`docs/ou-structure.md`](../ou-structure.md) and
[`docs/adrs/0001-ou-split.md`](../adrs/0001-ou-split.md): `Security`,
`Infrastructure`, `Workloads/{NonProd,Prod}`, `Deployments`, `Sandbox`,
`Suspended` (plus a hard-coded `Policy-Staging` OU in the org module).

### ⚠️ Pre-flight data conflicts to resolve BEFORE enrollment

These are real inconsistencies in the ground-truth files. They must be reconciled
first — CT enrollment keys on **account ID** and **root email**, so a wrong value
silently enrolls (or fails to enroll) the wrong account. Log them in
[conflict-analysis.md](./conflict-analysis.md):

1. **`dr` account ID mismatch.** `terragrunt/_org/account.hcl`'s `member_accounts`
   map says `dr.account_id = "666666666666"`, but `terragrunt/dr/account.hcl` says
   `aws_account_id = "444444444444"`. **CT must use the real ID** — confirm with
   `aws organizations list-accounts` before touching `dr`.
2. **Placeholder IDs.** Every non-sandbox account still carries a `# TODO: Replace
   with actual AWS … account ID` placeholder (`000000000000`, `111111111111`, …).
   Only `sandbox` (`007027391583`) is a real ID. **No enrollment can proceed on a
   placeholder ID.** The real IDs must be filled into `account.hcl` (and the
   `member_accounts` map) first.
3. **`member_accounts` map is incomplete.** It omits `security`, `log-archive`,
   `shared`, `sandbox`, `third-party`. Those five accounts exist only as
   `terragrunt/<account>/account.hcl` directories. Confirm whether they are *already
   members* of the live org (created out-of-band) or still need vending — this
   changes whether they are **enrolled** (existing member) or **provisioned** (new,
   via Account Factory / AFT).

---

## 2. Enrollment ORDER (all accounts)

**Ordering rationale.** Enroll the controls *substrate* first, then the things that
depend on it, with blast radius increasing as confidence grows:

1. **Rehearse in a throwaway account** — `sandbox` first (real ID, personal email,
   no platform data) as the dry run. See §5.
2. **Foundational security accounts** — `log-archive` then `audit/security`. CT's
   centralized CloudTrail + Config deliver *into* log-archive and aggregate *into*
   the audit account; nothing else can be cleanly enrolled until these are the CT
   controls home.
3. **Management account considerations** — the management account is the CT *home*;
   it is not "enrolled" like a member, but its hand-rolled org-trail / Config /
   GuardDuty / Security Hub *delegated-admin* wiring must be reconciled (§4) before
   member guardrails go live. Treat any management-account change as a dedicated,
   low-traffic-window operation.
4. **Shared infrastructure** — `network`, `shared` (Infrastructure OU).
5. **Non-prod workloads** — `dev`, `staging` (NonProd OU).
6. **Integrations** — `third-party` (Security OU, but low blast radius).
7. **Production / DR last, in a dedicated low-traffic window** — `prod`, then `dr`.

| Step | Account | OU (target) | Why this order | Prerequisites |
|---|---|---|---|---|
| 0 | `sandbox` | `Sandbox` | Rehearsal. Real ID `007027391583`, personal email, no platform data — safe place to discover CT/TF surprises. | Landing zone live; §5 dry-run plan ready. |
| 1 | `log-archive` | `Security` | CT central log destination. Must be the controls sink before any member's CloudTrail/Config is folded into CT. | Real ID confirmed; existing `cloudtrail`/`aws-config` S3 buckets inventoried (§4). |
| 2 | `security` | `Security` | CT audit/aggregator account (GuardDuty + Security Hub + Config delegated admin). Enroll right after log-archive so aggregation has a home. | log-archive enrolled; delegated-admin reconciliation plan (§4) approved. |
| 3 | `management` | *(CT home — not a member enrollment)* | Reconcile hand-rolled org-trail / Config / delegated-admin so member guardrails don't double-apply. Dedicated low-traffic window. | Steps 1–2 done; §4 `removed`/`moved` plan reviewed; CRITICAL-DECISION approval. |
| 4 | `network` | `Infrastructure` | Shared TGW/VPC hub. Enroll before workloads so guardrails are proven on a shared-but-non-prod account. | Steps 1–3 done; TGW change-freeze confirmed. |
| 5 | `shared` | `Infrastructure` | Shared services (ECR, ACM CA). Same tier as network, lower interdependency. | Step 4 done. |
| 6 | `dev` | `NonProd` (`Workloads/NonProd`) | First true workload enrollment; smallest blast radius of the workload accounts. | Steps 1–5 done; zero drift on `dev` (§3 pre-checks). |
| 7 | `staging` | `NonProd` (`Workloads/NonProd`) | Mirror of `dev`; validates the NonProd guardrail set end-to-end before prod. | Step 6 clean for ≥24h. |
| 8 | `third-party` | `Security` | External-integration account; enroll after non-prod is proven, before prod, since it shares the Security OU guardrails. | Steps 1–7 done. |
| 9 | `prod` | `Prod` (`Workloads/Prod`) | Production workloads. **Dedicated low-traffic window + change freeze.** | Steps 1–8 clean; CRITICAL-DECISION approval; rollback rehearsed in sandbox. |
| 10 | `dr` | `Prod` (`Workloads/Prod`) | DR enrolled last so prod stays recoverable throughout the whole exercise. **Resolve the ⚠️ ID mismatch first.** | Step 9 stable ≥24h; `dr` account ID confirmed against `list-accounts`. |

> The CT-best-practice "foundational accounts first, prod last" ordering matches
> the SCP guardrail matrix in [`docs/ou-structure.md`](../ou-structure.md): the
> `Security` OU accounts carry the broadest non-destructive guardrails, while
> `Prod` adds `DenyRootAccount` and the strictest controls — exactly the accounts
> we want enrolled last and most carefully.

---

## 3. Per-account procedure

The same four-phase procedure applies to every account. Account-specific notes
follow the table.

### 3.1 Pre-enrollment checklist (per account)

- [ ] **Real account ID confirmed.** `aws organizations list-accounts --query
      "Accounts[?Email=='<email>'].Id"` matches `aws_account_id` in
      `terragrunt/<account>/account.hcl`. No placeholder (§1 ⚠️).
- [ ] **State backed up.** Snapshot every Terragrunt unit's remote state for this
      account: `s3://tfstate-<account>-<region>` is versioned (it is, per
      `terraform/modules/state-backend`); record the current version IDs, and copy
      the `terraform.tfstate` objects to a dated `s3://…/_pre-ct-<date>/` prefix.
      Note the DynamoDB lock table `terraform-locks-<account>`.
- [ ] **Drift = zero.** `cd terragrunt/<account> && terragrunt run-all plan`
      reports **No changes** for every unit. Any pending diff must be applied or
      reverted *before* enrollment — CT will start managing some of these resources
      (§4) and a non-empty plan makes post-enrollment reconciliation ambiguous.
- [ ] **OAAR present.** `OrganizationAccountAccessRole` exists and is assumable from
      the management account (CT enrollment and `bootstrap/state-backend` both
      depend on it — see `bootstrap/state-backend/README.md`). For accounts created
      by AWS Organizations this is automatic; for invited accounts confirm it was
      created.
- [ ] **No in-flight changes.** No open PR touching this account's `terragrunt/`
      tree is mid-merge; CI `terragrunt-apply` (push-to-main) is idle; announce a
      change freeze for the account during its window.
- [ ] **SCP awareness.** Note which guardrails the account currently inherits from
      its OU (matrix in [`docs/ou-structure.md`](../ou-structure.md)). CT will add
      its own *mandatory/strongly-recommended* guardrails; confirm they do not
      conflict with the hand-rolled SCPs (esp. `RestrictToEURegions`,
      `DenyDisableCloudTrail`, `DenyGuardDutyChanges` from
      `terraform/modules/scps/main.tf`).

### 3.2 Enrollment steps (per account)

1. **Confirm OU target exists in CT.** The destination OU from the table in §2 must
   be a **CT-registered/governed OU**, not just a raw Organizations OU. Registering
   the OU in CT is a landing-zone task ([migration-plan.md](./migration-plan.md));
   verify before enrolling.
2. **Enroll the account into CT.** From CT (Account Factory → *Enroll account*, or
   the equivalent AFT enrollment path), enroll using the **confirmed account ID**
   and **root email**. CT assumes `OrganizationAccountAccessRole` to baseline the
   account.
3. **Place into the target OU.** Enrollment moves the account under the chosen CT
   governed OU. If the account is currently under a raw OU
   (`Security`/`Infrastructure`/`NonProd`/`Prod`/`Sandbox`), CT performs the move;
   record the source-parent OU ID for rollback (§3.4).
4. **Guardrail application.** CT applies the OU's mandatory + elected guardrails.
   Watch for **double-coverage** with the hand-rolled SCPs — CT detective/preventive
   guardrails may overlap `DenyDisableCloudTrail`, `RestrictToEURegions`, etc.
   Reconcile per §4 (prefer CT-managed; remove the now-redundant hand-rolled SCP
   attachment in a follow-up PR rather than leaving both).
5. **Let baselining settle.** CT deploys/links its CloudTrail, Config recorder +
   delivery channel into the account. Do **not** run `terragrunt apply` for this
   account until §4 reconciliation is staged — otherwise the hand-rolled
   `cloudtrail`/`aws-config` units will fight CT's.

### 3.3 Verification (per account)

- [ ] **Enrolled status.** Account shows **Enrolled** in CT (Account Factory /
      `Organizations` view); landing-zone drift check is green for the account.
- [ ] **Guardrails green.** All applied guardrails report **compliant** (or known,
      accepted exceptions) — no red detective guardrails.
- [ ] **Access still works.** SSO permission sets (`terraform/modules/sso`) still
      resolve; `OrganizationAccountAccessRole` still assumable; the
      `platform-design-terraform-*` CI role can still `terragrunt plan` the account
      (it is SCP-exempt by design in `scps/main.tf`).
- [ ] **CloudTrail flowing.** Management + data events landing in the CT log-archive
      bucket; no gap in the trail across the enrollment timestamp.
- [ ] **Config flowing.** Config recorder **ON**, delivery channel delivering, the
      account visible in the org Config aggregator in the audit account.
- [ ] **GuardDuty / Security Hub.** Account is a member under the delegated admin
      (security account), findings aggregating.
- [ ] **TF clean.** After §4 reconciliation, `terragrunt run-all plan` for the
      account is **No changes** again.

### 3.4 Per-account ROLLBACK

> CT enrollment is **largely reversible at the account level** via un-enroll, but
> some side effects are not. Know what is irreversible *before* you start.

**Reversible (standard rollback):**
1. **Un-enroll the account** from CT (Account Factory → *Unmanage/Un-enroll*). CT
   stops managing it and removes the guardrails it applied. The account remains in
   the org.
2. **Move the OU back.** `aws organizations move-account --account-id <ID>
   --source-parent-id <CT_OU_ID> --destination-parent-id <original_OU_ID>` using the
   source-parent recorded in §3.2 step 3. This restores the raw-OU SCP inheritance.
3. **Restore SCP attachment.** If §4 removed a hand-rolled SCP attachment in favour
   of a CT guardrail, re-apply it by reverting that follow-up PR (the `scps` module
   re-attaches via `for_each` over `ou_ids` — see `scps/main.tf`).
4. **Restore TF state ownership.** Re-import or un-`removed` the CloudTrail / Config
   resources CT took over (§4), then `terragrunt apply` the `cloudtrail` /
   `aws-config` units to bring them back under repo control.

**Irreversible / needs special recovery:**
- **CT baseline CloudTrail/Config resources** created in the account are CT-owned;
  un-enroll *detaches* governance but may leave orphaned CT roles/log streams.
  Recovery: delete the orphaned CT-created IAM roles + Config recorder only after
  confirming the hand-rolled `cloudtrail`/`aws-config` units are reapplied, so you
  never have **zero** trails/recorders (the `DenyDisableCloudTrail` SCP will also
  block careless deletion — by design).
- **Config recorder swap gaps.** If you delete CT's recorder before reapplying the
  hand-rolled one (or vice versa), there is a **compliance-history gap**. Sequence
  it: bring the replacement recorder up first, confirm delivery, *then* remove the
  other.
- **Delegated-admin reassignment** (GuardDuty / Security Hub / Config). If CT
  re-pointed delegated admin, un-enroll does not automatically restore the
  hand-rolled delegated-admin account; re-run the `guardduty-org` /
  `securityhub-org` / `config-org` units from management to reclaim it.
- **Root-email / account-ID** are immutable — a wrong enrollment can't be "renamed"
  out; un-enroll and redo with the correct identity.

---

## 4. Terraform / Terragrunt reconciliation

CT **takes over management of a defined set of org-wide controls.** The hand-rolled
Terraform that currently creates these must be removed from state (via `removed`
blocks) — or have ownership explicitly ceded — so post-enrollment `terragrunt plan`
stays clean instead of trying to re-create what CT now owns. The overlap surface,
derived from the actual modules:

| Hand-rolled unit / module | Resources today | CT takes over? | Reconciliation action |
|---|---|---|---|
| `cloudtrail` (`modules/cloudtrail`) — org trail | `aws_cloudtrail.org_trail`, its S3 bucket, KMS, CW log group, IAM | **Yes** — CT deploys its own org CloudTrail into log-archive | `removed {}` the `aws_cloudtrail` + delivery resources from state **after** confirming CT's trail is delivering; keep the S3 bucket if you want to retain historical logs (move it to a "retain" unit). |
| `aws-config` (`modules/aws-config`) — recorder, delivery channel, conformance pack, aggregator | `aws_config_configuration_recorder`, `…_delivery_channel`, `…_recorder_status`, `aws_config_organization_conformance_pack`, `aws_config_configuration_aggregator` | **Yes** — CT manages the Config recorder/delivery + its own conformance packs | Stage `removed {}` for the recorder/delivery/status so CT owns them. **Decide** whether to keep the repo's extra `aws_config_config_rule.*` (root_mfa, vpc_flow_logs, etc.) as *additive* detective controls or let CT guardrails replace them. |
| `guardduty-org` (`modules/guardduty-org`) | `aws_guardduty_organization_admin_account`, `…_organization_configuration`, detector + features | **Partial** — CT can manage GuardDuty enablement; delegated admin must agree | Keep delegated admin = `security` account in **one** place. If CT manages it, `removed {}` the `aws_guardduty_organization_admin_account`; otherwise tell CT not to. Do **not** leave both fighting over the admin assignment. |
| `security-hub` / `securityhub-org` | `aws_securityhub_organization_admin_account`, `…_organization_configuration`, finding aggregator | **Partial** — same delegated-admin contention as GuardDuty | Same rule: single owner of the delegated-admin + org-config. `removed {}` whichever side CT now owns. |
| `scps` (`modules/scps`) | `aws_organizations_policy.*` + `…_policy_attachment.*` | **Overlaps** CT guardrails (preventive SCPs) | Keep hand-rolled SCPs that have **no CT equivalent** (e.g. `RestrictToEURegions`, `DataPerimeter-DenyExternalPrincipals`, `RequireEBSEncryption`). For ones CT now provides (CloudTrail/GuardDuty disable-deny), drop the redundant attachment to stay under the **5-SCP-per-OU** limit called out in `scps/main.tf`. |
| `sso` (`modules/sso`) | `aws_ssoadmin_*` permission sets + assignments | **No** (CT enables IAM Identity Center; assignments stay yours) | No `removed` needed; just confirm CT didn't reset the Identity Center instance. Re-`apply` if CT re-provisioned the instance ARN (`account.hcl` `sso_instance_arn` is populated post-setup). |
| `organization` (`modules/organization`) | `aws_organizations_organization`, OUs, `aws_organizations_account.members` | **CT adopts the org** | CT does not delete your OUs, but it **governs** the ones you register. The `aws_organizations_account.members` resources and the `Suspended`/`Policy-Staging` OUs stay in repo state. Verify `feature_set = "ALL"` and the `enabled_policy_types` (SCP/TAG/RCP) are unchanged by CT. |
| `iam-baseline` (`modules/iam-baseline`) | password policy, EBS-encryption-by-default, Access Analyzer, account public-access-block | **Mostly no** | These are account-local. Keep them. Watch only for CT guardrails that duplicate the password-policy / public-access-block intent (additive is fine). |

**Mechanics for clean plans post-enrollment:**

- Use **`removed {}`** blocks (code-reviewed, reproducible in CI; confirm the
  Terraform version floor in `.terraform-version` supports them) **instead of
  `terraform state rm`** so the removal leaves a paper trail. `removed` deletes the
  resource *from state* while leaving the real (now CT-managed) resource in place.
- **Never** let the CI `terragrunt-apply` (push-to-main) run for an account between
  "CT enrolled" and "`removed` blocks merged" — that window is where the
  hand-rolled units would try to recreate CT-owned resources. Hold the account's
  change freeze until the reconciliation PR is merged.
- After each `removed` PR, re-run `terragrunt run-all plan` for the account and the
  `_org` units; the goal is **No changes** with the redundant resources gone from
  state but present in the cloud under CT.
- Record every `removed`/`moved` decision in [conflict-analysis.md](./conflict-analysis.md)
  so the conflict surface stays the single source of truth.

---

## 5. Dry-run / non-prod-first strategy

**Rehearse the entire procedure on `sandbox` (`007027391583`) before touching any
platform account.** Sandbox is uniquely suited: it has a **real account ID** (not a
placeholder), a personal root email (`gerasimowigor@gmail.com`), the `Sandbox` OU
guardrail profile, and **no production data or shared-services dependencies**.

**Dry-run sequence:**
1. Run the full §3.1 pre-enrollment checklist against `sandbox`. Capture exactly
   which `terragrunt run-all plan` units are noisy and how long state backup takes.
2. Enroll `sandbox` into CT into the `Sandbox` governed OU (§3.2). Time it; record
   every guardrail CT applies and any that conflict with the hand-rolled
   `Sandbox`-tier SCPs (`DenyRootAccount`, `RestrictToEURegions`).
3. Run the §4 reconciliation on sandbox's (smaller) control surface — practise the
   `removed {}` workflow end-to-end and confirm the post-enrollment plan goes clean.
4. **Rehearse the rollback (§3.4)** on sandbox: un-enroll, move OU back, restore SCP
   attachment, reapply hand-rolled units. Prove rollback works on a throwaway
   account before you ever need it on `prod`.
5. **Capture findings** in [migration-plan.md](./migration-plan.md) /
   [risk-register.md](./risk-register.md): real durations, surprise guardrail
   conflicts, the exact `removed` block set, any OAAR/permission gaps.

Only after the sandbox rehearsal is clean do you proceed to step 1 (`log-archive`)
of the §2 order. `dev` and `staging` then serve as the **second-tier rehearsal** on
real platform tooling before `prod`/`dr` — enroll `dev`, soak ≥24h, then `staging`,
soak ≥24h, and feed any new findings back into the plan before the prod window.

> **Production discipline:** `prod` (step 9) and `dr` (step 10), plus any
> management-account reconciliation (step 3), are **dedicated low-traffic-window**
> operations gated on an explicit CRITICAL-DECISION approval, with the rollback
> already rehearsed in sandbox and a change freeze announced. DR is intentionally
> last so production remains recoverable throughout the migration.
