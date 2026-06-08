output "lambda_function_name" {
  description = "Name of the scanner Lambda function."
  value       = aws_lambda_function.scanner.function_name
}

output "lambda_function_arn" {
  description = "ARN of the scanner Lambda function."
  value       = aws_lambda_function.scanner.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role assumed by the scanner Lambda."
  value       = aws_iam_role.scanner.arn
}

output "schedule_rule_arn" {
  description = "ARN of the EventBridge schedule rule that triggers the scanner."
  value       = aws_cloudwatch_event_rule.schedule.arn
}
