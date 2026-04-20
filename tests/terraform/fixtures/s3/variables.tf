variable "aws_region" {
  description = "AWS region for test resources"
  type        = string
  default     = "us-east-1"
}

variable "test_name" {
  description = "Name of the test for tagging"
  type        = string
  default     = "s3-integration-test"
}

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
  default     = true
}

variable "create_iam_policies" {
  description = "Create IAM policies for IRSA access"
  type        = bool
  default     = false
}

variable "logging_bucket_name" {
  description = "Target S3 bucket for access logging"
  type        = string
  default     = ""
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for the bucket"
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
