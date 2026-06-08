# -----------------------------------------------------------------------------
# ecr-pull-through-cache — outputs (ADR-0029)
# -----------------------------------------------------------------------------

output "pull_through_cache_prefixes" {
  description = "Map of upstream key to its local ECR repository prefix. Callers pull as <acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<image>."
  value       = { for k, r in aws_ecr_pull_through_cache_rule.this : k => r.ecr_repository_prefix }
}

output "pull_through_cache_rules" {
  description = "Map of upstream key to { prefix, upstream_registry_url, registry_id } for the created PTC rules."
  value = {
    for k, r in aws_ecr_pull_through_cache_rule.this : k => {
      prefix                = r.ecr_repository_prefix
      upstream_registry_url = r.upstream_registry_url
      registry_id           = r.registry_id
    }
  }
}

output "dockerhub_credential_secret_arns" {
  description = "Map of credentialed-upstream key to the Secrets Manager secret ARN holding its upstream credential (value injected out-of-band)."
  value       = { for k, s in aws_secretsmanager_secret.dockerhub : k => s.arn }
}

output "repository_creation_template_role_arn" {
  description = "ARN of the IAM role assumed by ECR PTC to create cached repositories, or null when the creation template is disabled."
  value       = try(aws_iam_role.template[0].arn, null)
}

output "scanning_configuration_registry_id" {
  description = "Registry ID the scanning configuration applies to, or null when scanning configuration is not managed by this module."
  value       = try(aws_ecr_registry_scanning_configuration.this[0].registry_id, null)
}
