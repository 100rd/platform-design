# sso (IAM Identity Center)

Manages permission sets, group lookups against the Identity Store, and
group-to-account assignments for AWS IAM Identity Center.

Closes #167. Builds on the original #6/#64 skeleton (which only had
permission sets) by adding:

- Customer-managed policy attachments per permission set
- Optional inline policies and permissions boundaries
- Group lookups via `aws_identitystore_group` data sources
- Account-level assignments wiring groups -> permission sets -> accounts

## Usage

See [`terragrunt/_org/_global/sso/terragrunt.hcl`](../../../terragrunt/_org/_global/sso/terragrunt.hcl)
for the live config and
[`docs/runbooks/sso-permission-sets.md`](../../../docs/runbooks/sso-permission-sets.md)
for the inventory of permission sets, groups, and assignments.

```hcl
module "sso" {
  source = "../../terraform/modules/sso"

  organization_id = "o-xxxxxxxxxx"
  member_accounts = {
    dev  = { account_id = "111111111111", email = "...", ou = "NonProd" }
    prod = { account_id = "333333333333", email = "...", ou = "Prod" }
  }

  permission_sets = {
    AdministratorAccess = {
      description      = "Full admin"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      inline_policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          { Sid = "DenyCreateSavingsPlan", Effect = "Deny",
            Action = "savingsplans:CreateSavingsPlan", Resource = "*" }
        ]
      })
    }
    ReadOnlyAccess = {
      description      = "Read-only"
      session_duration = "PT8H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
  }

  groups = {
    admins   = "PlatformAdmins"
    auditors = "SecurityAuditors"
  }

  assignments = [
    { group_key = "admins",   permission_set = "AdministratorAccess",
      target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "admins",   permission_set = "AdministratorAccess",
      target_type = "ACCOUNT", target_value = "prod" },
    { group_key = "auditors", permission_set = "ReadOnlyAccess",
      target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "auditors", permission_set = "ReadOnlyAccess",
      target_type = "ACCOUNT", target_value = "prod" },
  ]
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `organization_id` | string | (required) | Tagged onto every permission set |
| `member_accounts` | map(object) | `{}` | Resolves `target_type=ACCOUNT` short names to account IDs |
| `permission_sets` | map(object) | `{}` | name -> { description, session_duration, managed_policies, customer_managed_policies (optional), inline_policy_json (optional), permissions_boundary_managed_policy_arn (optional) } |
| `groups` | map(string) | `{}` | logical_key -> Identity Store group display name |
| `assignments` | list(object) | `[]` | group_key, permission_set, target_type ("ACCOUNT" or "AWS_ACCOUNT_ID"), target_value |
| `tags` | map(string) | `{}` | Tags to apply to permission sets |

## Outputs

| Name | Description |
|---|---|
| `sso_instance_arn` | SSO instance ARN |
| `identity_store_id` | Identity Store ID |
| `permission_set_arns` | name -> ARN map |
| `groups_resolved` | logical_key -> { group_id, display_name } |
| `assignment_count` | total number of assignments managed |

## Pre-conditions

The module enforces three precondition checks at plan time (via a
`terraform_data.validate_assignments` resource):

1. Every assignment's `target_value` resolves to a real account_id (when
   `target_type = ACCOUNT`).
2. Every assignment's `permission_set` exists in `var.permission_sets`.
3. Every assignment's `group_key` exists in `var.groups`.

If any of these fail, `terraform plan` exits with an actionable error before
making any API calls.

## Pre-requisites in AWS

- IAM Identity Center must be enabled in the management account's home
  region. The module reads the existing instance via
  `data.aws_ssoadmin_instances`.
- All groups referenced in `var.groups` must exist in the Identity Store
  (display names must match exactly). Provision them via SCIM from your
  IdP (preferred) or manually in the console.

## Tests

Run:
```bash
cd terraform/modules/sso
terraform test
```

The mock-provider test suite covers default-empty inputs and rejection of
invalid `target_type` values.

## Limitations

- AWS does not support OU targets for `aws_ssoadmin_account_assignment`.
  The module rejects `target_type = "OU"` at validate time. To grant a
  group access to a whole OU, enumerate its accounts in `assignments`.
- Customer-managed policies are referenced by `name` (and optional `path`),
  not ARN. The named policy must already exist in EVERY target account
  before SSO can attach it. There is no equivalent of `arn:aws:iam:::policy/`
  for org-wide CMPs.
- The module does not manage Identity Store users or groups themselves —
  those should come from your IdP via SCIM. Managing them in TF would fight
  with SCIM provisioning.

## Related

- `docs/runbooks/sso-permission-sets.md` — inventory and group/account matrix
- AWS IAM Identity Center docs: <https://docs.aws.amazon.com/singlesignon/>
