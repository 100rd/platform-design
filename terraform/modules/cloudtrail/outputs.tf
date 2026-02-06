# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Module Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "trail_arn" {
  description = "ARN of the CloudTrail organization trail"
  value       = aws_cloudtrail.org_trail.arn
}

output "trail_name" {
  description = "Name of the CloudTrail organization trail"
  value       = aws_cloudtrail.org_trail.name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Logs group for real-time trail analysis"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Logs group"
  value       = aws_cloudwatch_log_group.cloudtrail.arn
}

output "cloudtrail_cloudwatch_role_arn" {
  description = "ARN of the IAM role used by CloudTrail to write to CloudWatch Logs"
  value       = aws_iam_role.cloudtrail_cloudwatch.arn
}
