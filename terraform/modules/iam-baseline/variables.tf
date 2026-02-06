# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline Variables
# ---------------------------------------------------------------------------------------------------------------------
# All password policy defaults exceed PCI-DSS minimums for defense in depth.
# ---------------------------------------------------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for IAM resource names"
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
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
