variable "name_prefix" {
  description = "Prefix used in Lambda / EventBridge / IAM resource names. Use the account name + region for uniqueness."
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression. Default: weekly Monday 06:00 UTC."
  type        = string
  default     = "cron(0 6 ? * MON *)"
}

variable "report_s3_bucket" {
  description = "S3 bucket name where the JSON report is uploaded. Must already exist (typically the log-archive bucket)."
  type        = string
}

variable "report_s3_prefix" {
  description = "S3 prefix for report objects. Default groups by date for easy lifecycle policy."
  type        = string
  default     = "orphaned-resources"
}

variable "slack_sns_topic_arn" {
  description = "Optional SNS topic ARN to publish a summary message. The team's SNS->Slack relay subscribes to this topic. Empty disables Slack notification."
  type        = string
  default     = ""
}

variable "regions_to_scan" {
  description = "AWS regions to scan in each invocation. Default scans the four EU regions used by the platform."
  type        = list(string)
  default     = ["eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1"]
}

variable "checks_enabled" {
  description = "Toggle individual orphaned-resource checks. Each defaults to true; flip to false to skip."
  type = object({
    unattached_ebs_volumes    = optional(bool, true)
    unused_elastic_ips        = optional(bool, true)
    available_enis            = optional(bool, true)
    old_ebs_snapshots         = optional(bool, true)
    idle_nat_gateways         = optional(bool, true)
    unattached_load_balancers = optional(bool, true)
  })
  default = {}
}

variable "ebs_volume_min_age_days" {
  description = "Minimum age (days) for an unattached EBS volume to be flagged. Default 7 days suppresses transient detach/reattach noise."
  type        = number
  default     = 7
}

variable "ebs_snapshot_max_age_days" {
  description = "Snapshots older than this many days are flagged. Default 90."
  type        = number
  default     = 90
}

variable "lambda_memory_mb" {
  description = "Lambda memory size. The default is sized for an org-wide scan; tune down if scanning a single account."
  type        = number
  default     = 512
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. EventBridge may need a long timeout because cross-region scans serialise."
  type        = number
  default     = 600
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
