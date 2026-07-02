variable "project" {
  description = "Project name used in resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider"
  type        = string
}

variable "kms_key_arns" {
  description = "List of KMS key ARNs that ESO is allowed to use for decryption"
  type        = list(string)
}

variable "secrets_arns_prefix" {
  description = "ARN prefix for Secrets Manager secrets (e.g. arn:aws:secretsmanager:eu-west-1:123456789012:secret). When empty, a wildcard for the project is used."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
