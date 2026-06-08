# ---------------------------------------------------------------------------------------------------------------------
# AWS Budgets — Management Account (per-linked-account cost alerts)
# ---------------------------------------------------------------------------------------------------------------------
# Deployed in the management account. Creates one master monthly budget
# for the whole org plus one per-linked-account budget per member, with
# 50%/80%/100%/110% ACTUAL alerts + 100% FORECASTED alert.
#
# SNS topic ARN comes from a forthcoming notifications module (#178/#182);
# until that lands, alerts route to email-only via notification_emails.
#
# See issue #175.
# ---------------------------------------------------------------------------------------------------------------------

include "envcommon" {
  path           = find_in_parent_folders("_envcommon/budgets.hcl")
  expose         = true
  merge_strategy = "deep"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

inputs = {
  project      = "platform-design"
  account_name = "management"

  # Master org-wide monthly limit. Tune as the platform grows.
  monthly_budget_amount = "50000"

  # Per-member-account budgets. account_id values are sourced from the
  # member_accounts map in _org/account.hcl; placeholders until real IDs
  # land via AFT (#168).
  per_account_budgets = {
    network = {
      account_id = "555555555555"
      amount     = "2000"
    }
    security = {
      account_id = "777777777777"
      amount     = "1000"
    }
    log-archive = {
      account_id = "888888888888"
      amount     = "1500"
    }
    shared = {
      account_id = "999999999999"
      amount     = "2000"
    }
    third-party = {
      account_id = "121212121212"
      amount     = "500"
    }
    dev = {
      account_id = "111111111111"
      amount     = "5000"
    }
    staging = {
      account_id = "222222222222"
      amount     = "8000"
    }
    prod = {
      account_id = "333333333333"
      amount     = "20000"
    }
    dr = {
      account_id = "444444444444"
      amount     = "5000"
    }
  }

  # Per-service budgets — focus on the high-spend categories. Tune as
  # actual usage data arrives.
  per_service_budgets = {
    "Amazon Elastic Compute Cloud - Compute"          = "12000" # EKS nodes, EC2 fleet
    "Amazon Relational Database Service"              = "3000"  # RDS
    "Amazon Elastic Container Service for Kubernetes" = "1500"  # EKS control plane
    "Amazon Simple Storage Service"                   = "2000"  # S3 (logs, state, data)
    "AmazonCloudWatch"                                = "1500"  # Metrics + Logs ingestion
  }

  # Notification routing. Email-only until the SNS notifications module
  # lands; SNS topic ARNs flip on then.
  notification_emails = ["aws-billing-alerts@example.com"]
  sns_topic_arns      = []

  # Cost Anomaly Detection at $50 floor (higher than envcommon default
  # because the management account spans the whole org).
  anomaly_threshold_amount = "50"

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Component   = "cost-management"
  }
}
