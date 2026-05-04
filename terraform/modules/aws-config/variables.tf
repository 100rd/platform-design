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
# Organization aggregator + conformance pack (#162)
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_organization_aggregator" {
  description = "When true, create an aws_config_configuration_aggregator collecting findings from every member account. Typically applied in the security/aggregator account after Config admin has been delegated to it. Closes the #162 'Aggregator in security account' criterion."
  type        = bool
  default     = false
}

variable "organization_aggregator_name" {
  description = "Name of the organization aggregator (only used when enable_organization_aggregator = true)."
  type        = string
  default     = "platform-design-org-aggregator"
}

variable "enable_organization_conformance_pack" {
  description = "When true, deploy a baseline conformance pack across the organization. Must be applied in the org management account or in an account with delegated Config administration. Closes the #162 'Baseline conformance pack applied' criterion."
  type        = bool
  default     = false
}

variable "organization_conformance_pack_name" {
  description = "Name of the baseline conformance pack."
  type        = string
  default     = "platform-design-baseline-best-practices"
}

variable "baseline_conformance_pack_template_body" {
  description = "Inline YAML body for the baseline conformance pack. Mutually exclusive with baseline_conformance_pack_template_s3_uri."
  type        = string
  default     = ""
}

variable "baseline_conformance_pack_template_s3_uri" {
  description = "S3 URI of the baseline conformance pack template (e.g. an AWS-published 'Operational Best Practices for AWS Foundational Security Best Practices' template). Mutually exclusive with baseline_conformance_pack_template_body."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
