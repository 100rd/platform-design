# Module: `budgets`

AWS Budgets + Cost Anomaly Detection. Provides monthly cost budgets with
configurable thresholds and SNS/email notifications.

Closes part of issue #175.

## Resources created

- `aws_budgets_budget.monthly_total` — single per-account total monthly
  budget. ACTUAL-spend notifications at every threshold in
  `var.alert_thresholds`, plus an optional FORECASTED notification.
- `aws_budgets_budget.per_account` — one budget per entry in
  `var.per_account_budgets`. Used in the management account to set
  per-linked-account limits. Hard-coded 80% + 100% ACTUAL notifications.
- `aws_budgets_budget.per_service` — one budget per AWS service named
  in `var.per_service_budgets`. Useful for capping runaway spend on EKS,
  RDS, etc.
- `aws_ce_anomaly_monitor.account` + `aws_ce_anomaly_subscription.account` —
  ML-driven anomaly detection with a configurable absolute-dollar floor.

## Inputs (most-used)

| Variable | Default | Purpose |
|---|---|---|
| `project` | (required) | Used in budget naming. |
| `account_name` | `""` | Optional account name suffix. Empty -> generic project-level budget. |
| `monthly_budget_amount` | `"10000"` | USD limit for the master monthly budget. |
| `alert_thresholds` | `[50, 80, 100]` | Percentage thresholds for ACTUAL-spend alerts. |
| `forecasted_alert_threshold` | `100` | Percentage for FORECASTED alert. Set to 0 to disable. |
| `notification_emails` | `[]` | Email subscriber list. |
| `sns_topic_arns` | `[]` | SNS topic ARNs for fan-out (PagerDuty, Slack via Lambda relay, etc.). |
| `per_account_budgets` | `{}` | Map of `<name> -> {account_id, amount}`. Use in management account. |
| `per_service_budgets` | `{}` | Map of `<service-name> -> amount`. |
| `enable_anomaly_detection` | `true` | Toggle ML monitor. |
| `anomaly_threshold_amount` | `"20"` | Min absolute USD for an anomaly alert. |

See `variables.tf` for the full list.

## Usage via Terragrunt

A unit at `terragrunt/_org/_global/budgets/terragrunt.hcl` is provisioned
in the management account. It includes
`terragrunt/_envcommon/budgets.hcl` for shared inputs (alert thresholds,
forecasted alerting, anomaly detection) and overrides per-environment
values (master limit, per-account map).

```hcl
include "envcommon" {
  path           = find_in_parent_folders("_envcommon/budgets.hcl")
  expose         = true
  merge_strategy = "deep"
}

inputs = {
  project               = "platform-design"
  account_name          = "management"
  monthly_budget_amount = "50000"
  per_account_budgets   = { dev = { account_id = "...", amount = "5000" }, ... }
}
```

## Alert-routing roadmap

Today: email-only via `notification_emails`. SNS-via-Lambda Slack
relay lands with the centralized-notifications module under #178 / #182.
At that point, `sns_topic_arns` becomes the primary channel and email
becomes a fallback.

## Outputs

See `outputs.tf`. Useful surfaces:
- `monthly_budget_arn` — for cross-account observability dashboards.
- `anomaly_monitor_arn` — for hooking into a centralised cost dashboard.

## Cost

AWS Budgets: the first 2 budgets per account are free; subsequent budgets
cost $0.02/day each. Cost Anomaly Detection: free.
At the per-service + per-account fan-out used in the management account,
expected monthly cost: ~$15-30 (10-20 budgets × $0.60/month).
