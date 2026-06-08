# -----------------------------------------------------------------------------
# state-backend module — input variables
# -----------------------------------------------------------------------------

variable "account_name" {
  description = "Account short name used in resource naming (must match account.hcl in terragrunt/<account>/)."
  type        = string

  validation {
    condition = contains([
      "management",
      "network",
      "dev",
      "staging",
      "prod",
      "dr",
      "gcp-staging",
    ], var.account_name)
    error_message = "account_name must be one of: management, network, dev, staging, prod, dr, gcp-staging."
  }
}

variable "aws_region" {
  description = "AWS region where the state bucket lives. The DynamoDB lock table is global to the account but is created in this same region/provider."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. eu-west-1)."
  }
}

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN used to encrypt the S3 bucket (default encryption) and the DynamoDB lock table. If null/empty the AWS-managed `aws/s3` and `aws/dynamodb` keys are used. CIS-compliant either way."
  type        = string
  default     = null
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to retain noncurrent state object versions before expiration. 90 days balances rollback flexibility with storage cost."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 30 && var.noncurrent_version_retention_days <= 3650
    error_message = "noncurrent_version_retention_days must be between 30 and 3650 (10 years)."
  }
}

variable "enable_dynamodb_streams" {
  description = "Enable DynamoDB streams on the lock table. Required if you plan to add cross-region replicas via the state-backend-dr module (DDB Global Tables v2). Default false to keep #159 behaviour. Setting this to true is an in-place table update — no recreation."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources. Merged with module-defined tags (Name, Purpose, ManagedBy, Account)."
  type        = map(string)
  default     = {}
}
