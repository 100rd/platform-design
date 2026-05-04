# -----------------------------------------------------------------------------
# sso — outputs
# -----------------------------------------------------------------------------

output "sso_instance_arn" {
  description = "ARN of the SSO instance (Identity Center)."
  value       = local.sso_instance_arn
}

output "identity_store_id" {
  description = "Identity Store ID associated with the SSO instance."
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission-set name -> ARN."
  value       = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}

output "groups_resolved" {
  description = "Map of group logical-key -> resolved group ID and display name from the Identity Store."
  value = {
    for k, v in data.aws_identitystore_group.this :
    k => {
      group_id     = v.group_id
      display_name = v.display_name
    }
  }
}

output "assignment_count" {
  description = "Number of account assignments managed by this module."
  value       = length(aws_ssoadmin_account_assignment.this)
}
