output "secret_arn" {
  description = "ARN of the rotated secret. Reference this from an ESO ExternalSecret to sync the credential into a cluster."
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_name" {
  description = "Name of the rotated secret."
  value       = aws_secretsmanager_secret.this.name
}

output "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda function. This is what aws_secretsmanager_secret_rotation invokes; can also be passed to modules/secrets as rotation_lambda_arn for additional secrets."
  value       = aws_lambda_function.rotation.arn
}

output "rotation_lambda_name" {
  description = "Name of the rotation Lambda function."
  value       = aws_lambda_function.rotation.function_name
}

output "rotation_role_arn" {
  description = "ARN of the least-privilege IAM role assumed by the rotation Lambda."
  value       = aws_iam_role.rotation.arn
}

output "rotation_enabled" {
  description = "Whether automatic rotation is enabled for the secret."
  value       = aws_secretsmanager_secret_rotation.this.rotation_enabled
}

output "log_group_name" {
  description = "CloudWatch Logs group for the rotation Lambda."
  value       = aws_cloudwatch_log_group.rotation.name
}
