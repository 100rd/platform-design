# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-budget — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# GPU cost guardrail — REUSES the existing `budgets` module (ADR-0044 D4; no new module).
# 80/100/120% ACTUAL + FORECASTED-120 → SNS → Alertmanager → PagerDuty. Per-service
# scoped (EC2-Compute, EKS) to bound GPU spend. Account-scoped ONCE (not per region).
# CUR/OpenCost (ADR-0027) provides per-`system` attribution.
#
# Default-OFF (apply-gated): set gpu_platform_config.enabled = true in account.hcl.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/budgets"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  account_name        = local.account_vars.locals.account_name
  environment         = local.account_vars.locals.environment
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})
}

inputs = {
  project      = "platform-design"
  account_name = "${local.account_name}-gpu"

  # GPU monthly budget. Tune per account; the guardrail behaviour is what matters.
  monthly_budget_amount = try(local.gpu_platform_config.gpu_monthly_budget, "50000")

  # 80/100/120% ACTUAL + FORECASTED-120 (ADR-0044 D4 — the GKE 80/100/120 mirror).
  alert_thresholds           = [80, 100, 120]
  forecasted_alert_threshold = 120

  # Route to SNS → Alertmanager → PagerDuty (the budget paging path).
  sns_topic_arns      = try(local.gpu_platform_config.budget_sns_topic_arns, [])
  notification_emails = try(local.gpu_platform_config.budget_emails, ["platform-team@example.com"])

  # Scope GPU spend independently of the rest of the estate.
  per_service_budgets = {
    "Amazon Elastic Compute Cloud - Compute" = try(local.gpu_platform_config.gpu_ec2_budget, "40000")
    "Amazon Elastic Kubernetes Service"      = try(local.gpu_platform_config.gpu_eks_budget, "5000")
  }

  enable_anomaly_detection = true
  anomaly_threshold_amount = "500"

  tags = {
    "platform:system"     = "ml-platform"
    "platform:component"  = "cost-guardrail"
    "platform:owner"      = "team-ml-platform"
    "platform:env"        = local.environment
    "platform:managed-by" = "terragrunt"
  }
}
