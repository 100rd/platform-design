# -----------------------------------------------------------------------------
# _envcommon: AWS Budgets module — shared inputs and notification defaults
# -----------------------------------------------------------------------------
# See issue #175 for the full per-account cost-alerts design.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/budgets"

  defaults = {
    # Currency + budget cadence.
    currency  = "USD"
    time_unit = "MONTHLY"

    # Per-account default thresholds (% of forecasted/actual). Per-env units
    # override the absolute USD limit.
    notification_thresholds = [50, 80, 100, 110]

    # Notification channels — the SNS topic ARN comes from the env unit
    # (different topics per environment so prod alerts go to the on-call rotation).
    notification_types  = ["ACTUAL", "FORECASTED"]
    comparison_operator = "GREATER_THAN"

    # Default cost types — strip credit/refund to avoid noise.
    include_credit             = false
    include_discount           = true
    include_other_subscription = true
    include_recurring          = true
    include_refund             = false
    include_subscription       = true
    include_support            = true
    include_tax                = true
    include_upfront            = true
    use_amortized              = false
    use_blended                = false
  }
}

terraform {
  source = local.module_source
}

inputs = {
  currency                   = local.defaults.currency
  time_unit                  = local.defaults.time_unit
  notification_thresholds    = local.defaults.notification_thresholds
  notification_types         = local.defaults.notification_types
  comparison_operator        = local.defaults.comparison_operator
  include_credit             = local.defaults.include_credit
  include_discount           = local.defaults.include_discount
  include_other_subscription = local.defaults.include_other_subscription
  include_recurring          = local.defaults.include_recurring
  include_refund             = local.defaults.include_refund
  include_subscription       = local.defaults.include_subscription
  include_support            = local.defaults.include_support
  include_tax                = local.defaults.include_tax
  include_upfront            = local.defaults.include_upfront
  use_amortized              = local.defaults.use_amortized
  use_blended                = local.defaults.use_blended
}
