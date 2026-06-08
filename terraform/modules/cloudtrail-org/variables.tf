# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Module Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "trail_name" {
  description = "Name of the CloudTrail trail"
  type        = string
  default     = "org-trail"
}

variable "organization_id" {
  description = "AWS Organization ID — required for organization trail S3 bucket policy"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encrypting CloudTrail logs and CloudWatch Logs"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket Configuration
# ---------------------------------------------------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail log storage"
  type        = string
}

variable "s3_key_prefix" {
  description = "S3 key prefix for CloudTrail log files"
  type        = string
  default     = ""
}

variable "enable_object_lock" {
  description = "Enable S3 Object Lock (WORM) for tamper-proof log retention. PCI-DSS Req 10.5."
  type        = bool
  default     = true
}

variable "object_lock_retention_days" {
  description = "Number of days for Object Lock COMPLIANCE mode retention (irreversible — objects cannot be deleted until retention expires)"
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------------------------------------------------
# Lifecycle Configuration
# ---------------------------------------------------------------------------------------------------------------------

variable "lifecycle_standard_days" {
  description = "Days before transitioning logs to STANDARD_IA storage class"
  type        = number
  default     = 90
}

variable "lifecycle_glacier_days" {
  description = "Days before transitioning logs to GLACIER storage class"
  type        = number
  default     = 365
}

variable "lifecycle_expiration_days" {
  description = "Days before expiring logs. PCI-DSS Req 10.7 requires >= 365. Default 2555 (7 years)."
  type        = number
  default     = 2555

  validation {
    condition     = var.lifecycle_expiration_days >= 365
    error_message = "PCI-DSS Requirement 10.7: Audit trail history must be retained for at least 1 year (365 days)."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CloudWatch Logs
# ---------------------------------------------------------------------------------------------------------------------

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention period in days for real-time analysis"
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
