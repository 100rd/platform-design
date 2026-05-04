# -----------------------------------------------------------------------------
# state-backend-dr — input variables
# -----------------------------------------------------------------------------

variable "account_name" {
  description = "Account short name. Must match the account that owns the primary state-backend (resources are colocated in the same account, just in a second region)."
  type        = string

  validation {
    condition = contains([
      "management", "network", "dev", "staging", "prod", "dr", "gcp-staging",
    ], var.account_name)
    error_message = "account_name must be one of: management, network, dev, staging, prod, dr, gcp-staging."
  }
}

variable "primary_region" {
  description = "Region of the primary state bucket and DynamoDB lock table (where state-backend was applied)."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.primary_region))
    error_message = "primary_region must be a valid AWS region identifier (e.g. eu-west-1)."
  }
}

variable "dr_region" {
  description = "Region for the DR replica bucket and DynamoDB replica. Must be different from primary_region."
  type        = string
  default     = "eu-central-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.dr_region))
    error_message = "dr_region must be a valid AWS region identifier (e.g. eu-central-1)."
  }
}

variable "source_bucket_id" {
  description = "ID (name) of the primary S3 state bucket — value of state-backend's `state_bucket_name` output."
  type        = string
}

variable "source_bucket_arn" {
  description = "ARN of the primary S3 state bucket — value of state-backend's `state_bucket_arn` output."
  type        = string
}

variable "source_lock_table_arn" {
  description = "ARN of the primary DynamoDB lock table — value of state-backend's `lock_table_arn` output. The primary table MUST have streams enabled (set `enable_dynamodb_streams = true` on the state-backend module)."
  type        = string
}

variable "kms_key_arn_dr" {
  description = "Optional CMK in the DR region for encrypting the replica bucket. If null/empty, AWS-managed `aws/s3` is used. Note: the primary and replica buckets can use different keys — but if the source bucket is encrypted with a CMK, the replication role needs kms:Decrypt on it (handled below)."
  type        = string
  default     = null
}

variable "source_kms_key_arn" {
  description = "If the primary bucket uses a CMK, pass its ARN here so the replication role gets kms:Decrypt against it. Leave null if the primary uses the AWS-managed key."
  type        = string
  default     = null
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain noncurrent S3 versions in the replica bucket."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 30 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 30 and 3650 (10 years)."
  }
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
