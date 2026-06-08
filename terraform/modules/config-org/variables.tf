# Variables are passed through 1:1 to the underlying aws-config module.
# See terraform/modules/aws-config/variables.tf for full descriptions of
# defaults and validation rules.

variable "recorder_name" {
  description = "Name of the AWS Config configuration recorder."
  type        = string
  default     = "default"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket holding Config snapshots and history."
  type        = string
}

variable "s3_key_prefix" {
  description = "S3 key prefix for Config delivery channel objects."
  type        = string
  default     = "config"
}

variable "snapshot_delivery_frequency" {
  description = "Frequency for Config snapshot delivery (One_Hour, Three_Hours, Six_Hours, Twelve_Hours, TwentyFour_Hours)."
  type        = string
  default     = "TwentyFour_Hours"
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for encrypting the Config S3 bucket. Empty -> AES-256."
  type        = string
  default     = ""
}

variable "lifecycle_expiration_days" {
  description = "Days before expiring Config snapshots. PCI-DSS Req 10.7 requires >= 365."
  type        = number
  default     = 2555
}

variable "lifecycle_glacier_days" {
  description = "Days before transitioning Config snapshots to Glacier."
  type        = number
  default     = 365
}

variable "recording_all_resources" {
  description = "Record all resource types in the region."
  type        = bool
  default     = true
}

variable "include_global_resource_types" {
  description = "Include global resource types (IAM, etc.) — set true in exactly one region per account."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Organization aggregator (#162)
# ---------------------------------------------------------------------------

variable "enable_organization_aggregator" {
  description = "Enable the org-wide Config aggregator. Typically true in the security/aggregator account after Config admin has been delegated."
  type        = bool
  default     = false
}

variable "organization_aggregator_name" {
  description = "Name of the organization aggregator (only used when enable_organization_aggregator = true)."
  type        = string
  default     = "platform-design-org-aggregator"
}

# ---------------------------------------------------------------------------
# Baseline conformance pack (#162)
# ---------------------------------------------------------------------------

variable "enable_organization_conformance_pack" {
  description = "Deploy a baseline conformance pack across the organization. Provide either template_body or template_s3_uri."
  type        = bool
  default     = false
}

variable "organization_conformance_pack_name" {
  description = "Name of the baseline conformance pack."
  type        = string
  default     = "platform-design-baseline-best-practices"
}

variable "baseline_conformance_pack_template_body" {
  description = "Inline YAML body for the baseline conformance pack. Mutually exclusive with baseline_conformance_pack_template_s3_uri."
  type        = string
  default     = ""
}

variable "baseline_conformance_pack_template_s3_uri" {
  description = "S3 URI of the baseline conformance pack template (e.g. AWS-published 'Operational Best Practices for AWS Foundational Security Best Practices')."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default     = {}
}
