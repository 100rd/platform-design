# ---------------------------------------------------------------------------------------------------------------------
# Outputs — aws-ml-abac-iam
# ---------------------------------------------------------------------------------------------------------------------

output "role_arn" {
  description = "ARN of the ML workload IAM role. Null when the module is gated off (var.enabled=false)."
  value       = try(aws_iam_role.this[0].arn, null)
}

output "role_name" {
  description = "Name of the ML workload IAM role. Null when gated off."
  value       = try(aws_iam_role.this[0].name, null)
}

output "policy_arn" {
  description = "ARN of the least-privilege + ABAC permission policy. Null when gated off."
  value       = try(aws_iam_policy.this[0].arn, null)
}

output "platform_system" {
  description = "The platform:system value this role's ABAC condition matches on. Surfaced so the SOC2 evidence matrix and consuming stacks can confirm the role is scoped to a single system axis."
  value       = var.platform_system
}

output "abac_enforced" {
  description = "True when the module is enabled and at least one resource class (S3/KMS/Secrets) is granted — every such grant carries the ADR-0028 ABAC tag-match condition. Used by the *.tftest.hcl and the evidence matrix to assert ABAC is wired."
  value       = var.enabled && (length(var.artifact_bucket_arns) > 0 || length(var.kms_key_arns) > 0 || length(var.secret_arns) > 0)
}

output "platform_tags" {
  description = "Effective ADR-0028 taxonomy tags applied to the role/policy (base defaults merged with var.tags overrides)."
  value       = local.effective_tags
}
