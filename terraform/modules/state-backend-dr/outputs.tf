# -----------------------------------------------------------------------------
# state-backend-dr — outputs
# -----------------------------------------------------------------------------

output "replica_bucket_name" {
  description = "Name of the DR replica S3 bucket."
  value       = aws_s3_bucket.state_replica.id
}

output "replica_bucket_arn" {
  description = "ARN of the DR replica S3 bucket."
  value       = aws_s3_bucket.state_replica.arn
}

output "replica_bucket_region" {
  description = "Region the replica bucket lives in."
  value       = var.dr_region
}

output "replication_role_arn" {
  description = "ARN of the IAM role S3 uses to replicate from primary to replica."
  value       = aws_iam_role.replication.arn
}

output "replication_rule_id" {
  description = "ID of the replication rule attached to the primary bucket."
  value       = aws_s3_bucket_replication_configuration.state.id
}

output "lock_table_replica_arn" {
  description = "ARN of the DynamoDB lock-table replica in the DR region."
  value       = aws_dynamodb_table_replica.locks_dr.arn
}

output "lock_table_replica_region" {
  description = "Region of the DynamoDB lock-table replica."
  value       = var.dr_region
}

output "failover_summary" {
  description = "Convenience map summarising the failover endpoints."
  value = {
    primary = {
      bucket = var.source_bucket_id
      region = var.primary_region
    }
    replica = {
      bucket = aws_s3_bucket.state_replica.id
      region = var.dr_region
    }
    lock_table_global_arn  = var.source_lock_table_arn
    lock_table_replica_arn = aws_dynamodb_table_replica.locks_dr.arn
  }
}
