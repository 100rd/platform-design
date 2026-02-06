output "recorder_id" {
  description = "The ID of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.id
}

output "recorder_name" {
  description = "The name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Config snapshots"
  value       = aws_s3_bucket.config.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for Config snapshots"
  value       = aws_s3_bucket.config.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config.arn
}
