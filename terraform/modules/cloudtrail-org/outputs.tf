# -----------------------------------------------------------------------------
# cloudtrail-org — outputs (delegated to the underlying cloudtrail module)
# -----------------------------------------------------------------------------

output "trail_arn" {
  description = "ARN of the CloudTrail organization trail"
  value       = module.cloudtrail.trail_arn
}

output "trail_name" {
  description = "Name of the CloudTrail organization trail"
  value       = module.cloudtrail.trail_name
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing CloudTrail logs"
  value       = module.cloudtrail.s3_bucket_name
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudTrail logs"
  value       = module.cloudtrail.s3_bucket_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Logs group for real-time trail analysis"
  value       = module.cloudtrail.cloudwatch_log_group_name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Logs group"
  value       = module.cloudtrail.cloudwatch_log_group_arn
}

output "cloudtrail_cloudwatch_role_arn" {
  description = "ARN of the IAM role used by CloudTrail to write to CloudWatch Logs"
  value       = module.cloudtrail.cloudtrail_cloudwatch_role_arn
}
