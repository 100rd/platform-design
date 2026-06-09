# Control Tower ↔ Hand-Rolled Org: Governance Conflict Analysis

**Epic**: #168 — Control Tower + AFT migration
**Author**: Security Expert (planning only — no IaC, no apply)
**Status**: Draft for review
**Related**: [migration-plan.md](./migration-plan.md) · [ct-enrollment-runbook.md](./ct-enrollment-runbook.md) · [risk-register.md](./risk-register.md)

---

## 0. Ground truth (what is live today)

Control Tower (CT) is **not deployed**. The org is hand-rolled:

- `aws_organizations_organization.this` with `feature_set = "ALL"` and
  `enabled_policy_types = [SERVICE_CONTROL_POLICY, TAG_POLICY, RESOURCE_CONTROL_POLICY]`
  (`terraform/modules/organization/main.tf`, `terragrunt/_org/_global/organization/terragrunt.hcl`).
- **8 hand-rolled OUs**: `Security`, `Infrastructure`, `Workloads` (with nested
  `NonProd`, `Prod`), `Deployments`, `Sandbox`, plus a hard-coded `Suspended` and
  `Policy-Staging` OU created directly in the module
  (`docs/ou-structure.md`, ADR-0001).
- **5 member accounts only** — `network`, `dev`, `staging`, `prod`, `dr`
  (`terragrunt/_org/account.hcl`). **There is no `log-archive` and no `audit`
  account.** `docs/ou-structure.md` *intends* `security`, `log-archive`,
  `third-party` to live in the Security OU, but they are **not in the live
  `member_accounts` map** — they do not exist yet.
- **9 hand-rolled SCPs** in `terraform/modules/scps/main.tf`, attached per the
  matrix in `docs/ou-structure.md`. Workload OUs (`NonProd`, `Prod`) are at
  **5/5 slots**; root is at **4/5** (3 attached + inherited `FullAWSAccess`).
- **Self-managed IAM Identity Center** — 6 permission sets + 5 groups + 19
  assignments, all in the management account
  (`terraform/modules/sso/main.tf`, `terragrunt/_org/_global/sso/terragrunt.hcl`).
- **GuardDuty, Security Hub, Config delegated admin all point at the management
  account itself** (`delegated_admin_account_id = local.account_vars.locals.account_id`
  in `terragrunt/_org/_global/guardduty-org/terragrunt.hcl`; same pattern for
  security-hub / aws-config).
- **Hand-rolled org CloudTrail** `org-trail` in the management account, KMS-encrypted,
  S3 Object Lock, 7-year retention, CloudWatch Logs
  (`terragrunt/_org/_global/cloudtrail/terragrunt.hcl`).
- **Break-glass IAM user** in the management account, `prevent_destroy = true`,
  MFA-enforced, alarm sourced from the org-trail CloudWatch log group (ADR-0011).

CT, when **enrolling an existing org**, wants to **own** the governance primitives
this repo already hand-rolls: a Security OU + Sandbox OU, its own SCP guardrails,
IAM Identity Center, the delegated-admin assignments for the audit account, and a
centralized CloudTrail/Config pipeline to a Log Archive account. **Every one of
those is the conflict surface.**

---

## 1. OU model conflict

### What CT wants
- A **mandatory `Security` OU** containing two CT-created **shared accounts**:
  **Log Archive** and **Audit**. These are created/claimed by the CT landing
  zone and cannot be renamed.
- A **`Sandbox` OU** (CT's default "additional" OU for un-governed experimentation).
- A **Root → Foundational OUs → Additional OUs** topology. CT registers
  ("enrolls") existing OUs as *registered OUs*; any OU it governs, it expects to
  manage SCP/baseline drift on.
- CT does **not** support OUs nested more than one level under an enrolled OU for
  some baseline operations, and it manages its own OU for the management account
  context.

### What exists
- A `Security` OU already exists — but it is **empty of the accounts CT expects**
  (no Log Archive, no Audit account exist at all).
- A `Sandbox` OU already exists with its **own SCP profile** (region-restrict +
  deny-root + spend caps, ADR-0001).
- `Workloads/NonProd` and `Workloads/Prod` use a **two-level nesting**
  (`Workloads` parent → `NonProd`/`Prod` children).
- `Suspended` and `Policy-Staging` are **functional, hard-coded** OUs with
  bespoke SCP/RCP semantics that have no CT equivalent.

### The conflict
1. **Name collision on `Security` and `Sandbox`.** CT will try to create/claim a
   `Security` OU and a `Sandbox` OU. If it cannot reuse the same-named existing
   OUs cleanly, enrollment either fails or CT creates **duplicate** OUs, splitting
   governance. Even when it reuses them, CT will want to **place its Log
   Archive + Audit accounts** into the existing `Security` OU and apply **its**
   baseline there — colliding with our `Security` OU intent (audit/security-tooling
   accounts with our own SCP set).
2. **Missing shared accounts.** CT's landing zone is **predicated on** a Log
   Archive and an Audit account. They do not exist in `member_accounts`. CT will
   create them — adding two accounts the Terraform `organization` module does not
   know about, immediately producing **state drift** (accounts in the org that
   are not in `member_accounts`).
3. **Nested `Workloads/*`.** CT governs registered OUs but its baseline guardrail
   model is cleanest on top-level OUs. The `Workloads → NonProd/Prod` nesting,
   plus SCP inheritance math (ADR-0001 note: 5 attached + inherited FullAWSAccess),
   becomes harder to reason about once CT layers its own inherited guardrails on
   the parent.
4. **`Suspended` / `Policy-Staging` have no CT analog.** CT will not understand
   `DenyAllSuspended` (with its `OrganizationAccountAccessRole` carve-out) or the
   `Policy-Staging` RCP-staging pattern (ADR-0017). These OUs must remain
   **un-enrolled / self-managed** or CT drift-detection will flag them.

### Resolution direction
- **Pre-clean / adopt**: Rename or keep the existing `Security`/`Sandbox` OUs and
  let CT **adopt** them (register existing OUs) rather than create new ones; verify
  CT can reuse same-named OUs in *enroll-existing-org* mode before any apply.
- **Pre-create the shared accounts** (Log Archive, Audit) and add them to
  `member_accounts` **before** enrollment so Terraform state and CT agree, OR
  accept CT-created accounts and **import** them into the `organization` module
  state post-enrollment.
- **Carve-out**: Keep `Suspended` and `Policy-Staging` **outside CT governance**
  (do not enroll them); document them as Terraform-owned exceptions.
- Decision: see [migration-plan.md](./migration-plan.md) for adopt-vs-recreate.

---

## 2. SCP slot-limit collision

### What CT wants
- CT attaches **its own managed SCP guardrails** ("mandatory", "strongly
  recommended", "elective") to the OUs it governs. The mandatory guardrails
  include controls equivalent to several we hand-roll: deny disabling CloudTrail,
  deny disabling Config, deny changes to CT-managed resources, deny root for the
  shared accounts, region deny.
- CT attaches these as **additional SCP policies** on top of what is already
  attached — they consume the same **5-SCP-per-target budget**.

### What exists
Per `docs/scps.md` + `docs/ou-structure.md`:

| Target | Attached SCPs (+ inherited FullAWSAccess) | Slots used |
|---|---|---|
| Root | DenyS3Public, RequireEbsEncryption, DataPerimeter-DenyExternalPrincipals (+FullAWSAccess) | **4/5** |
| `NonProd` / `Prod` | DenyLeaveOrg, RestrictRegions, DenyDisableCloudTrail, DenyGuardDutyChanges, **DenyRootAccount** (+FullAWSAccess inherited) | **5/5** |
| `Security`/`Infrastructure`/`Deployments`/`Sandbox` | DenyLeaveOrg, RestrictRegions, DenyDisableCloudTrail, DenyGuardDutyChanges | 4/5 |
| `Suspended` | DenyAllSuspended | 1/5 |

### The conflict
1. **Workload OUs are at 5/5.** AWS hard-caps **5 SCPs per target including
   inherited**. If CT enrolls `NonProd`/`Prod` (or their `Workloads` parent) and
   tries to attach **even one** managed guardrail SCP, the **attach fails** and
   **enrollment of that OU fails / partially fails**. This is the single most
   likely hard-stop in the whole migration.
2. **Root is at 4/5.** CT also attaches guardrails referencing the org root /
   management context. One spare slot at root is thin; combined with ADR-0017's
   note that "the root SCP slots are at 5/5" once RCPs/declarative policies land,
   there is essentially **no headroom**.
3. **Functional overlap = double enforcement.** CT's managed guardrails duplicate
   our `DenyDisableCloudTrail`, `DenyGuardDutyChanges`, `DenyRootAccount`,
   region-restriction, and EBS-encryption controls. Running both is redundant and
   burns slots we cannot spare.
4. **`DenyAllSuspended` + OAAR carve-out and `DataPerimeter-DenyExternalPrincipals`
   are bespoke** — CT has no equivalent. They must survive the migration intact.
   The `OrganizationAccountAccessRole` carve-out in `DenyAllSuspended` is
   load-bearing for break-glass and offboarding; CT must not be allowed to
   overwrite or re-target the Suspended OU.

### Resolution direction (pre-clean BEFORE enrollment)
- **Consolidate/evict to free slots on workload OUs** *before* CT touches them:
  retire the SCPs that **CT's managed guardrails will replace** (CloudTrail,
  GuardDuty, region, root-deny) so each workload OU drops from 5/5 to ≤3/5,
  leaving room for CT's guardrails.
- **Map our SCP → CT guardrail** one-by-one; adopt CT's guardrail where it is
  equivalent-or-stronger, keep ours only where CT has **no** equivalent
  (`DataPerimeter-DenyExternalPrincipals`, `DenyAllSuspended`, `DenyLeaveOrg`).
- **Keep `Suspended` and `Policy-Staging` un-enrolled** so their bespoke SCPs/RCPs
  are never in CT's attach path.
- Leverage **ADR-0017** relief: RCPs (separate slot budget) and EC2 Declarative
  Policies (retires `require_imdsv2`) reduce SCP pressure — sequence those to
  land **before** CT enrollment of the workload OUs.
- Full slot-by-slot before/after mapping → [migration-plan.md](./migration-plan.md).

---

## 3. IAM Identity Center / SSO conflict

### What CT wants
- CT **provisions and manages IAM Identity Center** as part of the landing zone.
  In *enroll-existing-org* mode CT can **use an existing Identity Center
  instance**, but it expects to create its own **CT-managed permission sets**
  (e.g. `AWSAdministratorAccess`, `AWSReadOnlyAccess`,
  `AWSOrganizationsFullAccess`) and its own account-assignment groups for the
  shared accounts, and it manages the Identity Center **delegated administrator**
  setting.

### What exists
- A **fully self-managed Identity Center** (`terraform/modules/sso`): 6 permission
  sets (`AdministratorAccess`, `ReadOnlyAccess`, `PlatformEngineer`,
  `DeveloperAccess`, `BillingAccess`, `SecurityAuditAccess`), 5 groups looked up
  by display name from the Identity Store, and **19 explicit account assignments**
  enumerating groups → permission sets → accounts (AWS has no OU-target support,
  so each is per-account).
- The `AdministratorAccess` permission set carries a bespoke inline
  `DenyCreateSavingsPlan` guard and a `PT4H` session.

### The conflict
1. **Permission-set name overlap.** Our `AdministratorAccess` / `ReadOnlyAccess`
   names may collide with CT's `AWSAdministratorAccess` / `AWSReadOnlyAccess`
   conventions; even where names differ, **two sources now manage the same
   Identity Center instance** → drift between Terraform and CT.
2. **Assignment ownership.** Our 19 Terraform-managed assignments and CT's
   auto-created assignments for the Log Archive / Audit accounts will both write
   to the same instance. A CT re-baseline can **remove or alter** assignments
   Terraform thinks it owns → admins lose access or Terraform fights CT on every
   apply.
3. **Lock-out risk.** If CT takes over Identity Center and our group lookups
   (`data.aws_identitystore_group` by `DisplayName`) or assignments are
   invalidated, **human admin access via SSO can break** — the break-glass IAM
   user (ADR-0011) becomes the only path back in. This is the scenario the
   break-glass module exists for, but it must be **verified working before**
   enrollment.
4. **Region pinning.** Identity Center is a single-region service; CT pins the
   landing-zone home region. If our instance's region differs from CT's home
   region, CT cannot adopt it and would require a **new instance** (full
   re-provision of all permission sets/assignments).

### Resolution direction
- **Confirm CT adopts the existing Identity Center instance** (do not let CT
  stand up a second one). Verify home-region alignment first.
- **Decide a single owner per permission set**: let CT own the shared-account
  admin/readonly sets; keep our differentiated sets (`PlatformEngineer`,
  `DeveloperAccess`, `SecurityAuditAccess`, `BillingAccess`) Terraform-owned and
  **out of CT's managed name space**.
- **Snapshot all current assignments** and **verify break-glass IAM login works**
  immediately before the Identity Center step (gate in
  [ct-enrollment-runbook.md](./ct-enrollment-runbook.md)).
- Treat any Identity Center step as **non-rollback-safe** and stage it last.

---

## 4. Delegated-administrator reassignment conflict

### What CT wants
- CT mandates the **Audit account** as the **delegated administrator** for
  Security Hub, GuardDuty, Config aggregation, and IAM Access Analyzer, and the
  **Log Archive account** as the central logging sink. CT also registers itself
  (`controltower.amazonaws.com`) and the **StackSet/`member.org.stacksets`**
  service principals for trusted access.

### What exists
- **All three security-service delegated admins point at the management account
  itself** — not a security/audit account:
  - GuardDuty: `delegated_admin_account_id = local.account_vars.locals.account_id`
    (`guardduty-org/terragrunt.hcl`).
  - Security Hub: same pattern (`security-hub`/`securityhub-org`
    `delegated_admin_account_id`, no-op when equal to caller).
  - Config: aggregator `enable_config_aggregator` "typically in the
    security/aggregator account after Config admin has been delegated" — but the
    delegation has **not** been made to a separate account.
- `aws_service_access_principals` enables `cloudtrail`, `config`, `guardduty`,
  `sso`, `ram`, `securityhub` — but **NOT** `controltower.amazonaws.com` or
  `member.org.stacksets.cloudformation.amazonaws.com`.

### The conflict
1. **Delegation reassignment.** CT will **move** GuardDuty / Security Hub / Config
   delegated administration from the **management account** to the **Audit
   account**. AWS allows **one delegated admin per service** — reassigning it
   **de-registers the management account** as admin. Any Terraform that asserts
   `delegated_admin_account_id = <management>` will then **conflict** with CT and
   either fail to apply or fight CT for the role on every run.
2. **GuardDuty/Security Hub disruption window.** Re-homing the delegated admin can
   **drop the org-wide GuardDuty detector / Security Hub aggregation** during the
   handover — a **security-telemetry blind spot** while findings re-aggregate to
   the Audit account. Our `DenyGuardDutyChanges` SCP (no exemptions) may even
   **block CT's own re-association calls** if CT does not use an exempt principal.
3. **Missing trusted-access principals.** CT enrollment requires
   `controltower.amazonaws.com` (and StackSets) trusted access. They are not in
   `aws_service_access_principals`; CT will enable them, mutating the
   `organization` resource → Terraform drift.
4. **Audit account does not exist.** The delegated-admin target the whole model
   assumes is **not provisioned**.

### Resolution direction
- **Sequence**: provision the Audit account → enable CT trusted access principals
  (add `controltower.amazonaws.com`, StackSets to
  `aws_service_access_principals`) → let CT set Audit as delegated admin → **then**
  update Terraform to set `delegated_admin_account_id = <audit account>` to match,
  or **hand ownership of these settings to CT** and remove them from Terraform.
- **Temporarily relax `DenyGuardDutyChanges`** for the CT/security service-linked
  principal during the handover (or confirm CT's calls go through an exempt
  service principal) so re-association is not blocked. Re-tighten after.
- **Accept a planned telemetry-handover window**; schedule it and alert SOC.
- Step-by-step ordering → [ct-enrollment-runbook.md](./ct-enrollment-runbook.md).

---

## 5. Logging (CloudTrail / Config) centralization conflict

### What CT wants
- CT creates its **own organization CloudTrail** and **Config recorders/delivery**
  centralizing to the **Log Archive account** S3 buckets (CT-named, CT-KMS), with
  CT-managed retention and a CT-managed Config aggregator in the Audit account.

### What exists
- A hand-rolled org trail `org-trail` (`cloudtrail-org`) **in the management
  account**: KMS-encrypted, S3 `cloudtrail-audit-logs-<mgmt-account-id>`,
  **Object Lock** (PCI-DSS Req 10.5), 90d→1yr Glacier→7yr expiry, CloudWatch Logs
  365d. The **break-glass usage alarm** (ADR-0011) reads from **this trail's**
  CloudWatch log group.
- Hand-rolled `aws-config` / `config-org` with an org aggregator pattern keyed to
  a (not-yet-delegated) security account.
- `DenyDisableCloudTrail` SCP (**no exemptions**) blocks `StopLogging`,
  `UpdateTrail`, `DeleteTrail` on **any** trail.

### The conflict
1. **Two org trails.** Running CT's org trail **and** our `org-trail`
   simultaneously means **double CloudTrail ingestion / double cost** and two
   sources of truth. Consolidating to CT's Log Archive trail means
   **decommissioning `org-trail`** — but `DenyDisableCloudTrail` (no exemptions)
   will **block the `DeleteTrail`/`StopLogging`** needed to retire it. The SCP must
   be relaxed for the retirement, which is a **sensitive, auditable change**.
2. **Object Lock retention is irreversible.** The `org-trail` S3 bucket uses
   **Object Lock with 365-day retention**. Those objects **cannot be deleted**
   until retention expires — the legacy logs and bucket must be **retained
   read-only for up to a year + 7-year lifecycle**, even after CT takes over.
   Plan for parallel buckets, not a clean cutover.
3. **Break-glass alarm dependency.** The ADR-0011 break-glass alarm is wired to
   the **`org-trail` CloudWatch log group**. If `org-trail` is retired/moved to
   CT's Log Archive, the **alarm source disappears** and break-glass usage goes
   **un-alerted** until re-pointed at CT's trail's log group. This is a
   security-monitoring regression that must be fixed in the same change.
4. **Config recorder collision.** CT creates Config recorders org-wide; our
   `aws-config` recorders in member accounts will **conflict** (AWS allows one
   recorder per account/region) → CT enrollment of an account can fail if a
   recorder already exists, or our Terraform fights CT's recorder.

### Resolution direction
- **Run parallel, then cut over**: let CT stand up its Log Archive trail/Config;
  keep `org-trail` until CT's pipeline is verified delivering, then retire
  `org-trail` in a **dedicated, SCP-relaxing** change.
- **Retain the Object-Locked bucket read-only** for its full retention; do not
  attempt to delete it.
- **Re-point the break-glass alarm** to CT's Log Archive trail CloudWatch log
  group **in the same PR** that retires `org-trail`.
- **Pre-delete / import our Config recorders** in each account CT enrolls so CT's
  recorder does not collide; or let CT own Config and remove `aws-config`
  recorder management from Terraform.

---

## 6. Summary conflict matrix

| # | Area | CT wants | Exists today | Conflict | Resolution |
|---|---|---|---|---|---|
| 1 | OUs | Security OU w/ Log Archive+Audit, Sandbox OU, registered OUs | Security/Sandbox OUs (no shared accounts), nested Workloads/*, bespoke Suspended/Policy-Staging | Name collision, missing shared accounts, nested-OU baseline, no CT analog for Suspended/Policy-Staging | Adopt existing OUs; pre-create or import shared accounts; keep Suspended/Policy-Staging un-enrolled |
| 2 | SCPs | Attach managed guardrails to governed OUs | Workload OUs at **5/5**, root 4/5; 9 bespoke SCPs | **Slot exhaustion → guardrail attach fails**; functional duplication; bespoke SCPs must survive | Retire CT-equivalent SCPs to free slots; map ours→CT; keep DataPerimeter/DenyAllSuspended; use RCPs for relief (ADR-0017) |
| 3 | Identity Center | Manage Identity Center + CT permission sets | Self-managed 6 sets / 5 groups / 19 assignments | Name overlap, dual ownership, **admin lock-out risk**, region pinning | CT adopts existing instance; split ownership; verify break-glass first; stage last |
| 4 | Delegated admin | Audit account as GuardDuty/SecurityHub/Config admin | **Management account** is the admin for all three; Audit account absent | Reassignment de-registers mgmt; telemetry gap; DenyGuardDutyChanges may block CT; missing trusted-access principals | Provision Audit; add CT trusted principals; relax DenyGuardDutyChanges during handover; re-point Terraform |
| 5 | Logging | Org trail + Config → Log Archive | Hand-rolled `org-trail` in mgmt (Object Lock), Config recorders, alarm dependency | Two org trails, **DenyDisableCloudTrail blocks retirement**, Object-Lock irreversible, break-glass alarm + Config recorder collisions | Parallel-run then cut over; retain locked bucket; re-point alarm; resolve recorder collisions |

---

## 7. Cross-cutting: Terraform state vs CT-managed drift

CT manages its OUs/SCPs/accounts/Identity-Center/logging via **its own control
plane and CloudFormation StackSets** — *not* Terraform. Every primitive CT takes
over becomes a **drift source** against the `organization`, `scps`, `sso`,
`guardduty-org`, `security-hub`, `aws-config`, and `cloudtrail` Terraform state.
Each module must either (a) **stop managing** the primitive CT now owns
(`ignore_changes` / remove the resource / `terraform state rm`), or (b) be
**imported/reconciled** to CT's reality. Decide ownership per primitive **before**
enrollment — this is tracked as the highest-likelihood ongoing risk in
[risk-register.md](./risk-register.md) (R-006).
