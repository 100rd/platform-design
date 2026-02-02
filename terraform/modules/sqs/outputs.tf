output "queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "SQS queue name"
  value       = aws_sqs_queue.this.name
}

output "dlq_url" {
  description = "Dead-letter queue URL"
  value       = var.create_dlq ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  description = "Dead-letter queue ARN"
  value       = var.create_dlq ? aws_sqs_queue.dlq[0].arn : null
}

output "producer_policy_arn" {
  description = "IAM policy ARN for queue producers"
  value       = var.create_iam_policies ? aws_iam_policy.producer[0].arn : null
}

output "consumer_policy_arn" {
  description = "IAM policy ARN for queue consumers"
  value       = var.create_iam_policies ? aws_iam_policy.consumer[0].arn : null
}
