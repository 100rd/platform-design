# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline Variables
# ---------------------------------------------------------------------------------------------------------------------
# All password policy defaults exceed PCI-DSS minimums for defense in depth.
# ---------------------------------------------------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for IAM resource names (e.g. 'platform-' to produce 'platform-EnforceMFA')"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Password Policy Settings (PCI-DSS Req 8.2)
# ---------------------------------------------------------------------------------------------------------------------

variable "minimum_password_length" {
  description = "Minimum password length. PCI-DSS Req 8.2.3 requires >= 7; default 14 for defense in depth."
  type        = number
  default     = 14
}

variable "require_lowercase_characters" {
  description = "Require at least one lowercase letter"
  type        = bool
  default     = true
}

variable "require_uppercase_characters" {
  description = "Require at least one uppercase letter"
  type        = bool
  default     = true
}

variable "require_numbers" {
  description = "Require at least one numeric character"
  type        = bool
  default     = true
}

variable "require_symbols" {
  description = "Require at least one non-alphanumeric character"
  type        = bool
  default     = true
}

variable "max_password_age" {
  description = "Days before password expires. PCI-DSS Req 8.2.4 requires <= 90."
  type        = number
  default     = 90
}

variable "password_reuse_prevention" {
  description = "Number of previous passwords to remember. PCI-DSS Req 8.2.5 requires >= 4; default 24."
  type        = number
  default     = 24
}

variable "allow_users_to_change_password" {
  description = "Allow users to change their own password"
  type        = bool
  default     = true
}

variable "hard_expiry" {
  description = "Prevent users from changing expired passwords (requires admin reset). Set false for usability."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Access Analyzer (CIS 1.20)
# ---------------------------------------------------------------------------------------------------------------------

variable "analyzer_type" {
  description = "IAM Access Analyzer type. Use ORGANIZATION in the management account (requires Organizations), ACCOUNT in all others."
  type        = string
  default     = "ACCOUNT"

  validation {
    condition     = contains(["ORGANIZATION", "ACCOUNT"], var.analyzer_type)
    error_message = "analyzer_type must be ORGANIZATION or ACCOUNT."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# EBS Encryption (CIS 2.2.1)
# ---------------------------------------------------------------------------------------------------------------------

variable "ebs_kms_key_arn" {
  description = "ARN of a KMS key to use as the default EBS encryption key. Leave empty to use the AWS-managed key."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Account alias (CIS 1.1, #165)
# ---------------------------------------------------------------------------------------------------------------------

variable "account_alias" {
  description = "Account alias to set on the AWS account (lowercase, 3-63 chars, hyphens allowed). Empty to skip. Closes #165 'Account alias set' acceptance criterion."
  type        = string
  default     = ""

  validation {
    condition     = var.account_alias == "" || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.account_alias))
    error_message = "account_alias must be 3-63 chars, lowercase alphanumerics or hyphens, and must not start or end with a hyphen."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Root access key alarm (#165)
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_root_access_key_alarm" {
  description = "Create an AWS Config managed rule (`iam-root-access-key-check`) that flags non-compliant accounts whenever a root user has an access key. The rule fires periodically; non-compliance is surfaced via Config's findings stream and (when wired) SecurityHub. Closes #165 'Root access keys check (alarm if present)' acceptance criterion. Set to false in accounts where AWS Config is not yet enabled — the rule plan/applies fine but only evaluates once Config is recording."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to taggable resources in this module"
  type        = map(string)
  default     = {}
}
