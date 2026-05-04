# Outputs are delegated 1:1 to the underlying aws-config module.

output "recorder_name" {
  value       = module.config.recorder_name
  description = "Config configuration recorder name"
}

output "s3_bucket_name" {
  value       = module.config.s3_bucket_name
  description = "S3 bucket holding Config snapshots and history"
}

output "s3_bucket_arn" {
  value       = module.config.s3_bucket_arn
  description = "ARN of the Config S3 bucket"
}
