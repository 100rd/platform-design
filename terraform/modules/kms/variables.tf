variable "keys" {
  description = "Map of KMS key alias suffix to key configuration. Each entry creates one CMK with an alias."
  type = map(object({
    description             = string
    deletion_window_in_days = optional(number, 30)
    key_usage               = optional(string, "ENCRYPT_DECRYPT")
    admin_arns              = list(string)
    user_arns               = list(string)
  }))

  validation {
    condition     = alltrue([for k, v in var.keys : v.deletion_window_in_days >= 7 && v.deletion_window_in_days <= 30])
    error_message = "deletion_window_in_days must be between 7 and 30."
  }

  validation {
    condition     = alltrue([for k, v in var.keys : contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC"], v.key_usage)])
    error_message = "key_usage must be one of: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and alias prefix"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "dr", "management", "network"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, dr, management, network."
  }
}

variable "alias_prefix" {
  description = "Override prefix for KMS alias names. When non-empty, aliases are created as alias/<alias_prefix>/<key>. When empty, falls back to alias/<environment>/<key>. Use this to avoid alias collisions when multiple stacks share the same environment."
  type        = string
  default     = ""
}

variable "allow_destroy" {
  description = "When true, omits the IaC-layer lifecycle.prevent_destroy guard on KMS keys. Default false preserves deletion protection for all production and shared stacks. Test/minimal stacks that will be torn down may set this to true — AWS-native protection (deletion_window_in_days) and IAM still apply. NEVER set to true for platform/ or blockchain/ stacks."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags to apply to all KMS resources"
  type        = map(string)
  default     = {}
}
