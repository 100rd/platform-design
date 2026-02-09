output "secret_arns" {
  description = "Map of secret names to ARNs"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.arn }
}

output "rotation_enabled_secrets" {
  description = "List of secret names that have rotation enabled"
  value       = [for k, v in aws_secretsmanager_secret_rotation.rotation : k]
}

output "replica_status" {
  description = "Map of secret name to its replica details (region and status) for secrets with replication enabled"
  value = {
    for k, v in aws_secretsmanager_secret.secrets : k => [
      for r in v.replica : {
        region = r.region
        status = r.status
      }
    ] if length(v.replica) > 0
  }
}
