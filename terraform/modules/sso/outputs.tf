output "sso_instance_arn" {
  description = "SSO instance ARN"
  value       = local.sso_instance_arn
}

output "identity_store_id" {
  description = "Identity Store ID"
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission set name to ARN"
  value       = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}
