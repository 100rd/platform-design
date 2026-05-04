# SSO permission-set inventory

**Source of truth**: `terragrunt/_org/_global/sso/terragrunt.hcl` (drives the
`terraform/modules/sso` module).

This page documents each permission set, the AWS-managed policies attached,
session duration, target groups, and target accounts. Update it whenever the
terragrunt unit changes.

Closes #167.

---

## Permission sets

| Name | Session | Description | Managed policies | Inline policy |
|---|---|---|---|---|
| `AdministratorAccess` | PT4H | Full admin. Break-glass / on-call. | `AdministratorAccess` | `Deny savingsplans:CreateSavingsPlan` |
| `ReadOnlyAccess` | PT8H | Read-only audit/inspection. | `ReadOnlyAccess` | — |
| `PlatformEngineer` | PT8H | EKS, networking, observability. | `AmazonEKSClusterPolicy`, `AmazonVPCFullAccess`, `CloudWatchFullAccess` | — |
| `DeveloperAccess` | PT8H | Non-prod power user (no IAM). | `PowerUserAccess` | — |
| `BillingAccess` | PT4H | Cost reporting, mgmt account only. | `job-function/Billing` | — |
| `SecurityAuditAccess` | PT8H | SecurityAudit + ViewOnly across all accounts. | `SecurityAudit`, `job-function/ViewOnlyAccess` | — |

---

## Group -> permission-set -> account matrix

Group display names below must exist in Identity Center (provisioned via
SCIM from your IdP, or added manually in the AWS Console).

### `PlatformAdmins`
Full administrator access to every account. Use for break-glass, infra
emergencies, and platform-team on-call rotations.

| Permission set | Accounts |
|---|---|
| `AdministratorAccess` | network, dev, staging, prod, dr |

### `PlatformEngineers`
Day-to-day platform work: cluster ops, networking, deploys.

| Permission set | Accounts |
|---|---|
| `PlatformEngineer` | network, dev, staging |
| `ReadOnlyAccess` | prod, dr |

Rationale: production write access is gated through CI/CD (PR + apply-from-main),
not through console click-ops. Engineers have read-only into prod for incident
investigation.

### `Developers`
Application engineers building services on the platform.

| Permission set | Accounts |
|---|---|
| `DeveloperAccess` | dev, staging |
| `ReadOnlyAccess` | prod |

Rationale: PowerUserAccess minus IAM in non-prod is the AWS-recommended
balance for application engineers (full service usage, no privilege
escalation). Production reads enabled for debugging only.

### `SecurityAuditors`
Audit-only role for compliance and security review.

| Permission set | Accounts |
|---|---|
| `SecurityAuditAccess` | network, dev, staging, prod, dr |

`SecurityAuditAccess` combines `SecurityAudit` (read security configs) with
`job-function/ViewOnlyAccess` (read everything else) — strictly
non-mutating. Auditors cannot create CloudTrail or modify Config rules
through this PS; that's IAC territory.

### `BillingTeam`
Finance / FinOps role.

| Permission set | Accounts |
|---|---|
| `BillingAccess` | management (only) |

Consolidated billing lives in the management account. Per-account spend
breakdowns are visible from there via Cost Explorer.

---

## Adding a new permission set

1. Edit `terragrunt/_org/_global/sso/terragrunt.hcl`. Add an entry under
   `permission_sets`.
2. If it needs an inline policy or permissions boundary, set
   `inline_policy_json` (use `jsonencode(...)`) or
   `permissions_boundary_managed_policy_arn`.
3. If it needs a customer-managed policy attached, populate
   `customer_managed_policies`. The policy must already exist with that
   name in EVERY target account before assignment can succeed (SSO
   references CMPs by name+path, not ARN).
4. Add it to this page.
5. PR + merge through normal review.

## Adding a new group

1. Provision the group in Identity Center (SCIM or console). Confirm the
   display name.
2. Edit `terragrunt/_org/_global/sso/terragrunt.hcl`. Add an entry under
   `groups`. Pick a snake_case logical key.
3. Add `assignments` entries for the group.
4. Document the group above.
5. PR + merge.

## Removing access (offboarding)

The fastest correct path is **remove the user from the group in your IdP**
— SCIM propagates and AWS removes the user's access within minutes. No
Terraform change required.

For a permission-set or group-wide removal:
1. Delete the relevant `assignments` entries (or remove the whole group).
2. PR + merge. CI runs `terragrunt apply` which deletes the assignment.

---

## Notes on AWS limits

- Account assignment is N x M (groups x accounts) per permission set. With
  the matrix above (~20 assignments today) we're well under any limits, but
  watch out: `aws_ssoadmin_account_assignment` is one resource per
  (group, PS, account) tuple. Adding 1 group with 1 PS across all 5 accounts
  is +5 resources.
- AWS does not let you target an OU directly with an SSO assignment. The
  module rejects `target_type = "OU"` at validate-time. To grant a group
  access to "all of NonProd", enumerate the accounts.
- Permission sets are global to the SSO instance (which lives in one
  region — the management account's home region). Account assignments are
  region-less.

## See also

- [`terraform/modules/sso/`](../../terraform/modules/sso/) — module source
- AWS IAM Identity Center docs: <https://docs.aws.amazon.com/singlesignon/>
