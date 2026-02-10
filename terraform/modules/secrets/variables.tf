variable "secrets" {
  description = "Map of secrets to create. Key is the secret name. Each value specifies description, rotation, and replication settings."
  type = map(object({
    description     = string
    enable_rotation = optional(bool, false)
    replicate       = optional(bool, false)
  }))
  default = {}
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK for encrypting secrets at rest. Required for PCI-DSS Req 3.4."
  type        = string
  default     = null
}

variable "rotation_lambda_arn" {
  description = "ARN of the Lambda function that implements the Secrets Manager rotation protocol. Required when any secret has enable_rotation = true. Deploy a rotation Lambda before enabling rotation."
  type        = string
  default     = null
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations (PCI-DSS Req 3.6.4 recommends <= 90 days)"
  type        = number
  default     = 90

  validation {
    condition     = var.rotation_days >= 1 && var.rotation_days <= 365
    error_message = "rotation_days must be between 1 and 365."
  }
}

variable "replica_regions" {
  description = "List of regions to replicate secrets to. Each region needs its own KMS key for encryption."
  type = list(object({
    region     = string
    kms_key_id = string
  }))
  default = []
}

variable "force_overwrite_replica" {
  description = "Whether to overwrite a secret with the same name in the destination region during replication."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
