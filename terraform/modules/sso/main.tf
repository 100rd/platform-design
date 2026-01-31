# ---------------------------------------------------------------------------------------------------------------------
# IAM Identity Center (SSO)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# ---------------------------------------------------------------------------------------------------------------------
# Permission Sets
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.sso_instance_arn
  session_duration = each.value.session_duration

  tags = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = { for item in flatten([
    for ps_name, ps in var.permission_sets : [
      for policy_arn in ps.managed_policies : {
        key        = "${ps_name}-${policy_arn}"
        ps_name    = ps_name
        policy_arn = policy_arn
      }
    ]
  ]) : item.key => item }

  instance_arn       = local.sso_instance_arn
  managed_policy_arn = each.value.policy_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_name].arn
}
