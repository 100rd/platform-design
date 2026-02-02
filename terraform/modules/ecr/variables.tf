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
