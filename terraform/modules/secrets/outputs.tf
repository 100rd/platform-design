output "secret_arns" {
  description = "Map of secret names to ARNs"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.arn }
}

output "rotation_enabled_secrets" {
  description = "List of secret names that have rotation enabled"
  value       = [for k, v in aws_secretsmanager_secret_rotation.rotation : k]
}
