output "log_group_name" {
  description = "Name of the CloudWatch log group ingesting EKS control-plane logs."
  value       = aws_cloudwatch_log_group.cluster.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Firehose delivery stream forwarding logs to the central bucket."
  value       = aws_kinesis_firehose_delivery_stream.this.arn
}

output "firehose_role_arn" {
  description = "ARN of the IAM role assumed by Firehose for S3 + KMS access."
  value       = aws_iam_role.firehose.arn
}

output "subscription_role_arn" {
  description = "ARN of the IAM role used by the CloudWatch Logs subscription filter."
  value       = aws_iam_role.subscription.arn
}
