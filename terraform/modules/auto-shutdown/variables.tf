variable "project" {
  description = "Project name used in resource naming (e.g. 'platform-design')"
  type        = string
}

variable "environment" {
  description = "Environment name used in resource naming (e.g. 'dev', 'development')"
  type        = string
}

variable "enabled" {
  description = "Set to false to disable all auto-shutdown resources. Use false in staging/prod environments."
  type        = bool
  default     = true
}

variable "shutdown_schedule" {
  description = "EventBridge Scheduler cron expression for the shutdown schedule (UTC). Default: Mon-Fri 19:00 UTC."
  type        = string
  default     = "cron(0 19 ? * MON-FRI *)"
}

variable "startup_schedule" {
  description = "EventBridge Scheduler cron expression for the startup schedule (UTC). Default: Mon-Fri 07:30 UTC."
  type        = string
  default     = "cron(30 7 ? * MON-FRI *)"
}

variable "timezone" {
  description = "Timezone for EventBridge Scheduler schedules. Default UTC."
  type        = string
  default     = "UTC"
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting the Lambda CloudWatch log group. Leave empty to skip log encryption (suitable for dev)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources in this module"
  type        = map(string)
  default     = {}
}
