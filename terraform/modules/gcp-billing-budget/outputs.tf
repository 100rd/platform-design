output "budget_id" {
  description = "Full resource ID of the billing budget (billingAccounts/.../budgets/...)."
  value       = google_billing_budget.this.id
}

output "budget_name" {
  description = "Server-assigned budget name."
  value       = google_billing_budget.this.name
}

output "pubsub_topic_id" {
  description = "Full Pub/Sub topic ID the budget notifies. Subscribe the Alertmanager webhook bridge to this topic."
  value       = local.notification_topic_id
}

output "threshold_percentages" {
  description = "Threshold fractions configured on the budget (e.g. [0.8, 1.0, 1.2])."
  value       = var.threshold_percentages
}
