output "lambda_function_arn" {
  description = "ARN of the auto-shutdown Lambda function. Empty string when module is disabled."
  value       = var.enabled ? aws_lambda_function.auto_shutdown[0].arn : ""
}

output "lambda_function_name" {
  description = "Name of the auto-shutdown Lambda function. Empty string when module is disabled."
  value       = var.enabled ? aws_lambda_function.auto_shutdown[0].function_name : ""
}

output "scheduler_arns" {
  description = "Map of scheduler name to ARN for the shutdown and startup schedules. Empty map when module is disabled."
  value = var.enabled ? {
    shutdown = aws_scheduler_schedule.shutdown[0].arn
    startup  = aws_scheduler_schedule.startup[0].arn
  } : {}
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM execution role. Empty string when module is disabled."
  value       = var.enabled ? aws_iam_role.auto_shutdown_lambda[0].arn : ""
}
