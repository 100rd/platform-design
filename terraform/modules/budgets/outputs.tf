output "monthly_total_budget_id" {
  description = "ID of the monthly total budget for this account"
  value       = aws_budgets_budget.monthly_total.id
}

output "monthly_total_budget_name" {
  description = "Name of the monthly total budget"
  value       = aws_budgets_budget.monthly_total.name
}

output "per_account_budget_ids" {
  description = "Map of account name to per-linked-account budget ID (management account use)"
  value       = { for k, v in aws_budgets_budget.per_account : k => v.id }
}

output "per_service_budget_ids" {
  description = "Map of AWS service name to per-service budget ID"
  value       = { for k, v in aws_budgets_budget.per_service : k => v.id }
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor. Empty string when anomaly detection is disabled."
  value       = var.enable_anomaly_detection ? aws_ce_anomaly_monitor.account[0].arn : ""
}

output "anomaly_subscription_arn" {
  description = "ARN of the Cost Anomaly Detection subscription. Empty string when anomaly detection is disabled."
  value       = var.enable_anomaly_detection ? aws_ce_anomaly_subscription.account[0].arn : ""
}
