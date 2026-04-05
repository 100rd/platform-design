# ---------------------------------------------------------------------------------------------------------------------
# AWS Organization
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  enabled_policy_types          = var.enabled_policy_types
  aws_service_access_principals = var.aws_service_access_principals
}

# ---------------------------------------------------------------------------------------------------------------------
# Organizational Units — Top-level
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "top_level" {
  for_each = { for k, v in var.organizational_units : k => v if v.parent == "Root" }

  name      = each.key
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Organizational Units — Nested (one level deep)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "nested" {
  for_each = { for k, v in var.organizational_units : k => v if v.parent != "Root" }

  name      = each.key
  parent_id = aws_organizations_organizational_unit.top_level[each.value.parent].id

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Suspended / Quarantine OU
# ---------------------------------------------------------------------------------------------------------------------
# Accounts under investigation, decommissioned, or compromised are moved here.
# The deny-all-suspended SCP (in the scps module) is then attached to this OU.
# Only OrganizationAccountAccessRole can operate within suspended accounts for:
#   - Break-glass emergency operations
#   - Log/audit data retrieval before account closure
#   - Executing the offboarding runbook
#
# Usage: move an account here with:
#   aws organizations move-account --account-id ACCOUNT_ID \
#     --source-parent-id CURRENT_OU_ID --destination-parent-id SUSPENDED_OU_ID
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "suspended" {
  name      = "Suspended"
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = merge(var.tags, {
    Purpose = "quarantine"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Member Accounts
# ---------------------------------------------------------------------------------------------------------------------

locals {
  all_ous = merge(
    { for k, v in aws_organizations_organizational_unit.top_level : k => v.id },
    { for k, v in aws_organizations_organizational_unit.nested : k => v.id },
  )
}

resource "aws_organizations_account" "members" {
  for_each = var.member_accounts

  name      = each.key
  email     = each.value.email
  parent_id = local.all_ous[each.value.ou]

  role_name = "OrganizationAccountAccessRole"

  lifecycle {
    ignore_changes = [role_name]
  }

  tags = merge(var.tags, {
    Account = each.key
  })
}
