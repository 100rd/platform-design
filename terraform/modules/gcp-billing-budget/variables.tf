variable "billing_account_id" {
  description = "GCP billing account ID that owns the budget (format: XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "budget_display_name" {
  description = "Human-readable name for the budget shown in the GCP billing console."
  type        = string
  default     = "ml-infra-gpu-monthly-budget"
}

variable "monthly_amount" {
  description = "Specified monthly budget amount in units of currency_code (e.g. 10000 = 10,000 USD/month)."
  type        = number

  validation {
    condition     = var.monthly_amount > 0
    error_message = "monthly_amount must be greater than zero."
  }
}

variable "currency_code" {
  description = "ISO 4217 currency code for the budget amount. Must match the billing account currency."
  type        = string
  default     = "USD"
}

variable "gpu_project_ids" {
  description = "List of GPU project IDs to scope the budget filter to. Empty list = budget covers the whole billing account."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "threshold_percentages" {
  description = "Spend fractions (of monthly_amount) at which to fire budget alerts. Defaults to 80%, 100%, 120%."
  type        = list(number)
  default     = [0.8, 1.0, 1.2]
  nullable    = false

  validation {
    condition     = length(var.threshold_percentages) > 0
    error_message = "At least one threshold percentage must be provided."
  }

  validation {
    condition     = alltrue([for t in var.threshold_percentages : t > 0])
    error_message = "All threshold percentages must be greater than zero (expressed as fractions, e.g. 0.8 for 80%)."
  }
}

variable "create_pubsub_topic" {
  description = "Whether this module should create the Pub/Sub topic used for budget notifications. Set false to reuse an existing topic."
  type        = bool
  default     = true
}

variable "pubsub_topic_name" {
  description = "Short name of the Pub/Sub topic for budget notifications (used when create_pubsub_topic = true)."
  type        = string
  default     = "ml-infra-budget-alerts"
}

variable "pubsub_topic_id" {
  description = "Full Pub/Sub topic ID (projects/PROJECT/topics/NAME) to notify. Required when create_pubsub_topic = false; otherwise ignored."
  type        = string
  default     = null
}

variable "topic_project_id" {
  description = "Project in which to create the Pub/Sub notification topic when create_pubsub_topic = true."
  type        = string
  default     = null

  validation {
    condition     = var.topic_project_id != null
    error_message = "topic_project_id must be set so the notification topic and budget have a home project."
  }
}

variable "credit_types_treatment" {
  description = "How credits are handled in the budget actual spend. One of INCLUDE_ALL_CREDITS, EXCLUDE_ALL_CREDITS."
  type        = string
  default     = "INCLUDE_ALL_CREDITS"

  validation {
    condition     = contains(["INCLUDE_ALL_CREDITS", "EXCLUDE_ALL_CREDITS"], var.credit_types_treatment)
    error_message = "credit_types_treatment must be INCLUDE_ALL_CREDITS or EXCLUDE_ALL_CREDITS."
  }
}

variable "disable_default_iam_recipients" {
  description = "When true, only the Pub/Sub topic is notified (no emails to billing admins/users)."
  type        = bool
  default     = false
}

variable "labels" {
  description = "ADR-0028 platform labels applied to created resources (GCP label keys use underscores, e.g. platform_system = ml-infra)."
  type        = map(string)
  default     = {}
  nullable    = false
}
