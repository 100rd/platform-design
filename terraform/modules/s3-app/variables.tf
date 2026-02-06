variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "versioning_enabled" {
  description = "Enable versioning"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow force destroy of non-empty bucket"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the bucket"
  type        = list(any)
  default     = []
}

variable "create_iam_policies" {
  description = "Create IAM policies for IRSA access"
  type        = bool
  default     = true
}

variable "logging_bucket_name" {
  description = "Target S3 bucket for access logging (PCI-DSS Req 10.1). Empty string disables logging."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
