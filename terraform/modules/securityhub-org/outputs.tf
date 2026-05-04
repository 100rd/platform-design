output "delegated_admin_account_id" {
  description = "Configured delegated admin account ID (empty if not set)."
  value       = var.delegated_admin_account_id
}

output "finding_aggregator_enabled" {
  description = "Whether the finding aggregator is enabled."
  value       = var.enable_finding_aggregator
}
