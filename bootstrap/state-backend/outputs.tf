output "state_bucket_name" {
  description = "S3 bucket created for Terraform state. Matches the bucket name expected by terragrunt/root.hcl."
  value       = module.state_backend.state_bucket_name
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = module.state_backend.state_bucket_arn
}

output "lock_table_name" {
  description = "DynamoDB lock table name. Matches the name expected by terragrunt/root.hcl."
  value       = module.state_backend.lock_table_name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table."
  value       = module.state_backend.lock_table_arn
}

output "terragrunt_remote_state_config" {
  description = "Configuration that terragrunt/root.hcl will use to talk to this backend."
  value       = module.state_backend.terragrunt_remote_state_config
}
