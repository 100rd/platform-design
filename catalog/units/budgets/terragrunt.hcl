# ---------------------------------------------------------------------------------------------------------------------
# Budgets — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Per-account monthly AWS cost budgets with email + anomaly detection alerts.
# Deploy in every account. In the management account, also populate per_account_budgets
# to set individual member-account limits.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/budgets"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
}

inputs = {
  project      = "platform-design"
  account_name = local.account_name

  # Set account-appropriate monthly budget limits
  monthly_budget_amount = "2000"

  # TODO: Replace with your team's platform alert email
  notification_emails = ["platform-team@example.com"]

  alert_thresholds           = [50, 80, 100]
  forecasted_alert_threshold = 100

  enable_anomaly_detection = true
  anomaly_threshold_amount = "20"

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    Purpose     = "cost-control"
  }
}
