variable "account_name" {
  description = "Account short name (must match terragrunt/<account>/account.hcl)."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the state bucket will be created."
  type        = string
  default     = "eu-west-1"
}

variable "kms_key_arn" {
  description = "Optional CMK ARN for state bucket and lock table encryption. If null, AWS-managed keys are used."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to merge onto bootstrap resources."
  type        = map(string)
  default     = {}
}
