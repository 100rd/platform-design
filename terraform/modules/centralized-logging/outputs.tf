output "bucket_name" {
  description = "Name of the primary log-archive bucket."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the primary log-archive bucket."
  value       = aws_s3_bucket.this.arn
}

output "dr_bucket_name" {
  description = "Name of the DR-region replicated bucket. Null when replication disabled."
  value       = length(aws_s3_bucket.dr) > 0 ? aws_s3_bucket.dr[0].bucket : null
}

output "dr_bucket_arn" {
  description = "ARN of the DR-region replicated bucket. Null when replication disabled."
  value       = length(aws_s3_bucket.dr) > 0 ? aws_s3_bucket.dr[0].arn : null
}

output "log_source_prefixes" {
  description = "Map of log-source name to its S3 prefix in the bucket. Pass to consumers (CloudTrail, Config, VPC Flow, EKS audit) so they write to the right path."
  value       = var.log_source_prefixes
}

output "replication_role_arn" {
  description = "ARN of the IAM role used by S3 replication. Null when replication disabled."
  value       = length(aws_iam_role.replication) > 0 ? aws_iam_role.replication[0].arn : null
}
