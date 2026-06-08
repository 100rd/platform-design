variable "bucket_name" {
  description = "Name of the centralized log archive S3 bucket. Must be globally unique. Convention: <project>-log-archive-<account_id>-<region>."
  type        = string
}

variable "primary_region" {
  description = "Primary AWS region. Used for the S3 bucket and KMS key."
  type        = string
  default     = "eu-west-1"
}

variable "dr_region" {
  description = "DR region for cross-region replication. Empty disables replication."
  type        = string
  default     = "eu-central-1"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for SSE-KMS on the primary bucket. Provisioned by terraform/modules/kms (alias: alias/log-archive)."
  type        = string
}

variable "dr_kms_key_arn" {
  description = "ARN of the KMS key used for SSE-KMS on the DR-region bucket. Provisioned by terraform/modules/kms in the DR region. Empty disables replication."
  type        = string
  default     = ""
}

variable "enable_replication" {
  description = "Enable cross-region replication to the DR bucket."
  type        = bool
  default     = true
}

variable "enable_object_lock" {
  description = "Enable Object Lock GOVERNANCE retention on the primary bucket. Required for PCI-DSS Req 10.5 (immutable audit trail). Object Lock CANNOT be disabled once enabled."
  type        = bool
  default     = true
}

variable "object_lock_mode" {
  description = "Object Lock mode: GOVERNANCE (admin can override) or COMPLIANCE (no override, no shorter retention)."
  type        = string
  default     = "GOVERNANCE"
  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "Object Lock mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Default Object Lock retention period in days. Applied to every new object."
  type        = number
  default     = 365
}

variable "lifecycle_standard_days" {
  description = "Days to keep objects in S3 STANDARD before transitioning to STANDARD_IA."
  type        = number
  default     = 30
}

variable "lifecycle_ia_days" {
  description = "Days in STANDARD_IA before transitioning to GLACIER (must be >= lifecycle_standard_days + 30)."
  type        = number
  default     = 90
}

variable "lifecycle_glacier_days" {
  description = "Days in STANDARD before transitioning to GLACIER (used when lifecycle_ia_days is 0 or skipped)."
  type        = number
  default     = 365
}

variable "lifecycle_expiration_days" {
  description = "Days before objects are deleted. Set to 0 to disable expiration."
  type        = number
  default     = 2555 # ~7 years (PCI-DSS retention requirement)
}

variable "trusted_writer_account_ids" {
  description = "List of AWS account IDs allowed to write to this bucket (CloudTrail, Config, VPC Flow, EKS audit). Each account's CloudTrail-org / Config / etc. roles need s3:PutObject on the corresponding prefix."
  type        = list(string)
  default     = []
}

variable "log_source_prefixes" {
  description = "Map of log-source-name to S3 prefix. Each source's principals get a scoped Put policy on its prefix only. Common prefixes: cloudtrail/, config/, vpc-flow/, eks-audit/, eks-authenticator/."
  type        = map(string)
  default = {
    cloudtrail        = "cloudtrail"
    config            = "config"
    vpc-flow          = "vpc-flow"
    eks-audit         = "eks-audit"
    eks-authenticator = "eks-authenticator"
  }
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
