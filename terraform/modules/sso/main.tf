# ---------------------------------------------------------------------------
# IAM Identity Center (SSO)
# ---------------------------------------------------------------------------
# Manages permission sets, customer-/managed-policy attachments, optional
# inline policies and permissions boundaries, group lookups against the
# Identity Store, and account-level assignments wiring groups -> permission
# sets -> accounts.
#
# Closes #167. Builds on the original #6/#64 skeleton (permission sets only).
# ---------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # Account-name -> account-id map for `target_type = ACCOUNT` resolution.
  account_id_by_name = { for k, v in var.member_accounts : k => v.account_id }

  # Resolved assignment targets — flatten to a stable map keyed by
  # group/permission-set/target so `for_each` produces a deterministic plan.
  resolved_assignments = {
    for a in var.assignments :
    "${a.group_key}|${a.permission_set}|${a.target_type}|${a.target_value}" => {
      group_key      = a.group_key
      permission_set = a.permission_set
      account_id = a.target_type == "AWS_ACCOUNT_ID" ? a.target_value : (
        contains(keys(local.account_id_by_name), a.target_value)
        ? local.account_id_by_name[a.target_value]
        : null
      )
    }
  }
}

# Sanity guard: every assignment must resolve to a real account_id.
resource "terraform_data" "validate_assignments" {
  lifecycle {
    precondition {
      condition = alltrue([
        for k, v in local.resolved_assignments : v.account_id != null
      ])
      error_message = "One or more assignments reference an unknown account short-name. Add it to var.member_accounts or use target_type = AWS_ACCOUNT_ID with a 12-digit ID."
    }
    precondition {
      condition = alltrue([
        for k, v in local.resolved_assignments : contains(keys(var.permission_sets), v.permission_set)
      ])
      error_message = "One or more assignments reference an undefined permission_set."
    }
    precondition {
      condition = alltrue([
        for k, v in local.resolved_assignments : contains(keys(var.groups), v.group_key)
      ])
      error_message = "One or more assignments reference an undefined group_key."
    }
  }
}

# ---------------------------------------------------------------------------
# Identity Store group lookups (real group IDs)
# ---------------------------------------------------------------------------
data "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Permission Sets
# ---------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.sso_instance_arn
  session_duration = each.value.session_duration

  # OrganizationId is included in tags primarily so the variable has an
  # actual referent (otherwise tflint flags it unused). It is still part of
  # the public input contract for the terragrunt unit and may be consumed
  # programmatically by audit tooling looking at permission-set tags.
  tags = merge(var.tags, {
    OrganizationId = var.organization_id
  })
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for item in flatten([
      for ps_name, ps in var.permission_sets : [
        for policy_arn in ps.managed_policies : {
          key        = "${ps_name}|${policy_arn}"
          ps_name    = ps_name
          policy_arn = policy_arn
        }
      ]
    ]) : item.key => item
  }

  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_name].arn
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {
  for_each = {
    for item in flatten([
      for ps_name, ps in var.permission_sets : [
        for cmp in coalesce(ps.customer_managed_policies, []) : {
          key     = "${ps_name}|${cmp.path}|${cmp.name}"
          ps_name = ps_name
          name    = cmp.name
          path    = cmp.path
        }
      ]
    ]) : item.key => item
  }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_name].arn

  customer_managed_policy_reference {
    name = each.value.name
    path = each.value.path
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = {
    for ps_name, ps in var.permission_sets :
    ps_name => ps.inline_policy_json
    if ps.inline_policy_json != null && ps.inline_policy_json != ""
  }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value
}

resource "aws_ssoadmin_permissions_boundary_attachment" "this" {
  for_each = {
    for ps_name, ps in var.permission_sets :
    ps_name => ps.permissions_boundary_managed_policy_arn
    if ps.permissions_boundary_managed_policy_arn != null && ps.permissions_boundary_managed_policy_arn != ""
  }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  permissions_boundary {
    managed_policy_arn = each.value
  }
}

# ---------------------------------------------------------------------------
# Account assignments (group -> permission set -> account)
# ---------------------------------------------------------------------------
resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.resolved_assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn

  principal_id   = data.aws_identitystore_group.this[each.value.group_key].group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
