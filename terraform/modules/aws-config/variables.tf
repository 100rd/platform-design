# ---------------------------------------------------------------------------------------------------------------------
# AWS Config Module Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  type        = string
  default     = "default"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for Config snapshots and history"
  type        = string
}

variable "s3_key_prefix" {
  description = "S3 key prefix for Config delivery channel objects"
  type        = string
  default     = "config"
}

variable "snapshot_delivery_frequency" {
  description = "Frequency for Config snapshot delivery. Valid values: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  type        = string
  default     = "TwentyFour_Hours"

  validation {
    condition     = contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.snapshot_delivery_frequency)
    error_message = "snapshot_delivery_frequency must be one of: One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS Encryption
# ---------------------------------------------------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encrypting the Config S3 bucket. If empty, AES-256 is used."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Lifecycle
# ---------------------------------------------------------------------------------------------------------------------

variable "lifecycle_expiration_days" {
  description = "Days before expiring Config snapshots. PCI-DSS Req 10.7 requires >= 365."
  type        = number
  default     = 2555

  validation {
    condition     = var.lifecycle_expiration_days >= 365
    error_message = "PCI-DSS Requirement 10.7: Config history must be retained for at least 1 year (365 days)."
  }
}

variable "lifecycle_glacier_days" {
  description = "Days before transitioning Config snapshots to Glacier"
  type        = number
  default     = 365
}

# ---------------------------------------------------------------------------------------------------------------------
# Recording Settings
# ---------------------------------------------------------------------------------------------------------------------

variable "recording_all_resources" {
  description = "Record all resource types in the region"
  type        = bool
  default     = true
}

variable "include_global_resource_types" {
  description = "Include global resource types (IAM, etc.) — enable in one region only"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
