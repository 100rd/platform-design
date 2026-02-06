# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Organization Module Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "delegated_admin_account_id" {
  description = "AWS account ID to delegate GuardDuty administration to. If empty, the current account is used."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Feature Toggles
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_s3_protection" {
  description = "Enable S3 data event protection. Detects suspicious access patterns to S3 buckets."
  type        = bool
  default     = true
}

variable "enable_eks_audit_log_monitoring" {
  description = "Enable EKS audit log monitoring. Analyzes Kubernetes audit logs for suspicious activity."
  type        = bool
  default     = true
}

variable "enable_eks_runtime_monitoring" {
  description = "Enable EKS runtime monitoring. Detects runtime threats in EKS clusters via a security agent."
  type        = bool
  default     = true
}

variable "enable_malware_protection" {
  description = "Enable malware protection for EBS volumes. Scans EBS volumes attached to EC2/ECS for malware."
  type        = bool
  default     = true
}

variable "enable_rds_protection" {
  description = "Enable RDS login activity monitoring. Detects anomalous login behavior to RDS databases."
  type        = bool
  default     = true
}

variable "enable_lambda_protection" {
  description = "Enable Lambda network activity monitoring. Detects suspicious network activity from Lambda functions."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Organization Settings
# ---------------------------------------------------------------------------------------------------------------------

variable "auto_enable_org_members" {
  description = "Automatically enable GuardDuty for new organization member accounts."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
