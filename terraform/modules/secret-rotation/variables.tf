# ---------------------------------------------------------------------------------------------------------------------
# secret-rotation — input variables
# ---------------------------------------------------------------------------------------------------------------------

variable "name" {
  description = "Base name for the rotated secret and its rotation Lambda. Used to derive the secret name, Lambda function name, and IAM role name."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,200}$", var.name))
    error_message = "name must be 1-200 chars of [a-zA-Z0-9/_+=.@-] (Secrets Manager name charset)."
  }

  nullable = false
}

variable "secret_description" {
  description = "Human-readable description of the credential this module rotates (e.g. 'app-db primary credentials')."
  type        = string
  default     = "Rotated credential managed by the secret-rotation module"
}

variable "kms_key_arn" {
  description = "ARN of the customer-managed KMS CMK used to encrypt the secret at rest AND grant the rotation Lambda kms:Decrypt / kms:GenerateDataKey. Required for least-privilege KMS scoping (ADR-0031)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:kms:", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid KMS key ARN (arn:aws:kms:...)."
  }

  nullable = false
}

# ---------------------------------------------------------------------------------------------------------------------
# Rotation schedule (rotation_rules) — provide automatically_after_days OR schedule_expression (not both).
# Verified against the aws_secretsmanager_secret_rotation provider docs.
# ---------------------------------------------------------------------------------------------------------------------

variable "rotation_after_days" {
  description = "Number of days between automatic rotations. Mutually exclusive with rotation_schedule_expression. Set to null when using a schedule_expression. PCI-DSS Req 3.6.4 recommends <= 90 days."
  type        = number
  default     = 30

  validation {
    condition     = var.rotation_after_days == null || try(var.rotation_after_days >= 1 && var.rotation_after_days <= 365, false)
    error_message = "rotation_after_days must be null or between 1 and 365."
  }
}

variable "rotation_schedule_expression" {
  description = "A cron() or rate() expression for the rotation schedule. Mutually exclusive with rotation_after_days. Leave null to use rotation_after_days."
  type        = string
  default     = null
}

variable "rotation_duration" {
  description = "Length of the rotation window in hours (e.g. '3h'). Optional; null means Secrets Manager chooses the window."
  type        = string
  default     = null
}

variable "rotate_immediately" {
  description = "Whether to rotate the secret immediately when rotation is enabled. Provider default is true. Set false to wait for the next scheduled window (Secrets Manager runs a testSecret step instead)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Rotation Lambda
# ---------------------------------------------------------------------------------------------------------------------

variable "lambda_runtime" {
  description = "Lambda runtime for the rotation function. Default python3.12 matches the AWS-provided RDS rotation templates."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler entrypoint. For a custom handler this is module.function; for an AWS RDS rotation template it is lambda_function.lambda_handler."
  type        = string
  default     = "index.lambda_handler"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds. Rotation functions need enough time to reach the DB and complete the four rotation steps."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 256
}

variable "lambda_package_path" {
  description = "Optional path to a prebuilt rotation Lambda deployment package (.zip), e.g. an AWS-provided RDS single-user / alternating-user template. When null, the module packages the bundled placeholder handler. Provide a real template before enabling rotation in production."
  type        = string
  default     = null
}

variable "lambda_environment_variables" {
  description = "Additional environment variables for the rotation Lambda. SECRETS_MANAGER_ENDPOINT is always injected by the module."
  type        = map(string)
  default     = {}
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the rotation Lambda. -1 means unreserved (account default)."
  type        = number
  default     = -1
}

# ---------------------------------------------------------------------------------------------------------------------
# VPC config — so the rotation Lambda can reach a PRIVATE RDS instance.
# Placeholders are accepted for plan/validate; wire real subnets/SG via the Terragrunt unit.
# ---------------------------------------------------------------------------------------------------------------------

variable "vpc_subnet_ids" {
  description = "Private subnet IDs the rotation Lambda's ENIs are placed in. Must have a route to the target RDS instance. Empty list disables VPC config (only valid when the secret target is publicly reachable)."
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "Security group IDs attached to the rotation Lambda's ENIs. The SG (or the DB SG) must allow egress to the DB port (e.g. 5432/tcp for PostgreSQL)."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------------------------------------------------
# Observability / housekeeping
# ---------------------------------------------------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the rotation Lambda log group, in days."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
