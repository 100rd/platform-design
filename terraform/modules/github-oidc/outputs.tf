output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider. Reference this in custom OIDC role trust policies."
  value       = module.github_oidc_provider.arn
}

output "terraform_role_arn" {
  description = "ARN of the Terraform CI/CD role (plan + apply). Use with aws-actions/configure-aws-credentials role-to-assume."
  value       = module.terraform_role.arn
}

output "terraform_role_name" {
  description = "Name of the Terraform CI/CD IAM role"
  value       = module.terraform_role.name
}

output "readonly_role_arn" {
  description = "ARN of the read-only role (PR plan). Use with aws-actions/configure-aws-credentials role-to-assume."
  value       = module.readonly_role.arn
}

output "readonly_role_name" {
  description = "Name of the read-only IAM role"
  value       = module.readonly_role.name
}

output "ecr_push_role_arn" {
  description = "ARN of the ECR push role (container image builds). Use with aws-actions/configure-aws-credentials role-to-assume."
  value       = module.ecr_push_role.arn
}

output "ecr_push_role_name" {
  description = "Name of the ECR push IAM role"
  value       = module.ecr_push_role.name
}

output "ecr_push_policy_arn" {
  description = "ARN of the ECR push IAM policy"
  value       = aws_iam_policy.ecr_push.arn
}
