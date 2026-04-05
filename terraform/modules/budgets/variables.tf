variable "project" {
  description = "Project name used in budget naming (e.g. 'platform-design')"
  type        = string
}

variable "account_name" {
  description = "Account short name used in budget naming. Leave empty for a generic project-level budget."
  type        = string
  default     = ""
}

variable "monthly_budget_amount" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "10000"
}

variable "notification_emails" {
  description = "Email addresses for budget and anomaly notifications"
  type        = list(string)
  default     = []
}

variable "sns_topic_arns" {
  description = "SNS topic ARNs for budget notifications (use in addition to or instead of email)"
  type        = list(string)
  default     = []
}

variable "alert_thresholds" {
  description = "List of ACTUAL spend percentage thresholds that trigger notifications"
  type        = list(number)
  default     = [50, 80, 100]
}

variable "forecasted_alert_threshold" {
  description = "Percentage threshold for FORECASTED spend alert. Set to 0 to disable."
  type        = number
  default     = 100
}

variable "per_account_budgets" {
  description = "Map of account name to budget config. Used in the management account to set per-linked-account limits."
  type = map(object({
    account_id = string
    amount     = string
  }))
  default = {}
}

variable "per_service_budgets" {
  description = "Map of AWS service name (as shown in Cost Explorer) to monthly USD budget limit"
  type        = map(string)
  default     = {}
}

variable "enable_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection monitor and daily email subscription"
  type        = bool
  default     = true
}

variable "anomaly_threshold_amount" {
  description = "Minimum absolute dollar amount of a spend anomaly before an alert is sent"
  type        = string
  default     = "20"
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
