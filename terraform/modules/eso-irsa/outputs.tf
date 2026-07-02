output "role_arn" {
  description = "ARN of the IAM role for External Secrets Operator (use in serviceAccount.annotations)"
  value       = module.eso_irsa_role.iam_role_arn
}

output "role_name" {
  description = "Name of the IAM role for External Secrets Operator"
  value       = module.eso_irsa_role.iam_role_name
}

output "policy_arn" {
  description = "ARN of the IAM policy granting Secrets Manager read access"
  value       = aws_iam_policy.eso_secrets_manager.arn
}
