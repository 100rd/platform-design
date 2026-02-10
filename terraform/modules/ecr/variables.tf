variable "repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "IMMUTABLE"
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain"
  type        = number
  default     = 30
}

variable "force_delete" {
  description = "Force delete repository even if it contains images"
  type        = bool
  default     = false
}

variable "encryption_type" {
  description = "Encryption type for ECR repositories. KMS provides stronger encryption with CMK management. Valid values: AES256, KMS."
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either AES256 or KMS."
  }
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for ECR repository encryption. Only used when encryption_type is KMS. When null with KMS encryption, AWS uses the default aws/ecr key."
  type        = string
  default     = null
}

variable "cross_account_arns" {
  description = "List of AWS account ARNs allowed to pull images"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
