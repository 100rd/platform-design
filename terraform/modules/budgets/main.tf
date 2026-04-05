# ---------------------------------------------------------------------------------------------------------------------
# AWS Budgets + Cost Anomaly Detection
# ---------------------------------------------------------------------------------------------------------------------
# Monthly cost budgets with configurable thresholds and SNS/email notifications.
# Supports:
#   - Per-account total monthly budget
#   - Per-linked-account budgets (management account use case)
#   - Per-service budgets
#   - ML-based Cost Anomaly Detection
# ---------------------------------------------------------------------------------------------------------------------

locals {
  budget_name = var.account_name != "" ? "${var.project}-${var.account_name}-monthly-total" : "${var.project}-monthly-total"
}

# Monthly total budget for this account
resource "aws_budgets_budget" "monthly_total" {
  name         = local.budget_name
  budget_type  = "COST"
  limit_amount = var.monthly_budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Dynamic ACTUAL spend notifications at each configured threshold
  dynamic "notification" {
    for_each = toset([for t in var.alert_thresholds : tostring(t)])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = tonumber(notification.value)
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.notification_emails
      subscriber_sns_topic_arns  = var.sns_topic_arns
    }
  }

  # FORECASTED alert (optional — disable by setting forecasted_alert_threshold = 0)
  dynamic "notification" {
    for_each = var.forecasted_alert_threshold > 0 ? [var.forecasted_alert_threshold] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.notification_emails
      subscriber_sns_topic_arns  = var.sns_topic_arns
    }
  }

  tags = var.tags
}

# Per-linked-account budgets (management account use case: one budget per member)
resource "aws_budgets_budget" "per_account" {
  for_each = var.per_account_budgets

  name         = "${var.project}-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = each.value.amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "LinkedAccount"
    values = [each.value.account_id]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
    subscriber_sns_topic_arns  = var.sns_topic_arns
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
    subscriber_sns_topic_arns  = var.sns_topic_arns
  }

  tags = var.tags
}

# Per-service budgets
resource "aws_budgets_budget" "per_service" {
  for_each = var.per_service_budgets

  name         = "${var.project}-${each.key}-monthly"
  budget_type  = "COST"
  limit_amount = each.value
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "Service"
    values = [each.key]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 90
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.notification_emails
    subscriber_sns_topic_arns  = var.sns_topic_arns
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# AWS Cost Anomaly Detection — ML-based spend anomaly monitor + subscription
# ---------------------------------------------------------------------------

resource "aws_ce_anomaly_monitor" "account" {
  count = var.enable_anomaly_detection ? 1 : 0

  name              = "${var.project}-${var.account_name != "" ? var.account_name : "org"}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = var.tags
}

resource "aws_ce_anomaly_subscription" "account" {
  count = var.enable_anomaly_detection ? 1 : 0

  name      = "${var.project}-${var.account_name != "" ? var.account_name : "org"}-anomaly-subscription"
  frequency = "DAILY"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.account[0].arn,
  ]

  subscriber {
    type    = "EMAIL"
    address = length(var.notification_emails) > 0 ? var.notification_emails[0] : "platform-team@example.com"
  }

  dynamic "subscriber" {
    for_each = slice(var.notification_emails, min(1, length(var.notification_emails)), length(var.notification_emails))
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  dynamic "subscriber" {
    for_each = var.sns_topic_arns
    content {
      type    = "SNS"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [var.anomaly_threshold_amount]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = var.tags
}
