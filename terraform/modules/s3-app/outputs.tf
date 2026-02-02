output "bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "readwrite_policy_arn" {
  description = "IAM policy ARN for read-write access"
  value       = var.create_iam_policies ? aws_iam_policy.readwrite[0].arn : null
}

output "readonly_policy_arn" {
  description = "IAM policy ARN for read-only access"
  value       = var.create_iam_policies ? aws_iam_policy.readonly[0].arn : null
}
