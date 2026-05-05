# -----------------------------------------------------------------------------
# _envcommon: AWS Budgets module — shared inputs and notification defaults
# -----------------------------------------------------------------------------
# See issue #175 for the per-account cost-alerts design and
# terraform/modules/budgets/variables.tf for the full input contract.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/budgets"

  defaults = {
    # Monthly total budget in USD — overridden per env in the consuming unit.
    monthly_budget_amount = "10000"

    # ACTUAL-spend tier alerts. 50% / 80% / 100% as the issue's acceptance
    # criteria call for; 110% catches the over-run case.
    alert_thresholds = [50, 80, 100, 110]

    # FORECASTED alert at 100% — fires before the actual breach.
    forecasted_alert_threshold = 100

    # Cost Anomaly Detection — ML-driven. Default on with a $20 floor so
    # we don't spam on minor variation.
    enable_anomaly_detection = true
    anomaly_threshold_amount = "20"
  }
}

terraform {
  source = local.module_source
}

inputs = {
  monthly_budget_amount      = local.defaults.monthly_budget_amount
  alert_thresholds           = local.defaults.alert_thresholds
  forecasted_alert_threshold = local.defaults.forecasted_alert_threshold
  enable_anomaly_detection   = local.defaults.enable_anomaly_detection
  anomaly_threshold_amount   = local.defaults.anomaly_threshold_amount
}
