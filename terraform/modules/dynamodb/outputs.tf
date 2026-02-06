output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.this.id
}

output "readwrite_policy_arn" {
  description = "IAM policy ARN for DynamoDB read-write access via IRSA"
  value       = var.create_iam_policies ? aws_iam_policy.readwrite[0].arn : null
}

output "readonly_policy_arn" {
  description = "IAM policy ARN for DynamoDB read-only access via IRSA"
  value       = var.create_iam_policies ? aws_iam_policy.readonly[0].arn : null
}
