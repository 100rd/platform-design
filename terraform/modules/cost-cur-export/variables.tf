# ---------------------------------------------------------------------------------------------------------------------
# cost-cur-export module variables
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# AWS context
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for the S3 bucket and Athena workgroup. CUR report definitions are always created in us-east-1 — if this differs, supply a us-east-1 provider alias."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# CUR / S3
# ---------------------------------------------------------------------------

variable "cur_s3_bucket_name" {
  description = "Name of the S3 bucket that receives CUR Parquet files. Must be globally unique."
  type        = string
}

variable "cur_report_name" {
  description = "Name of the CUR report definition (also used as the S3 path component and Glue table base name)."
  type        = string
  default     = "opencost-cur"
}

variable "cur_report_prefix" {
  description = "S3 key prefix under which CUR files are delivered (e.g. 'cur')."
  type        = string
  default     = "cur"
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to destroy non-empty S3 buckets. Set false in production."
  type        = bool
  default     = false
}

variable "lifecycle_ia_days" {
  description = "Days before transitioning CUR objects to STANDARD_IA storage class."
  type        = number
  default     = 90
}

variable "lifecycle_expiration_days" {
  description = "Days before expiring CUR objects. Retain at minimum 13 months for year-over-year comparison."
  type        = number
  default     = 400

  validation {
    condition     = var.lifecycle_expiration_days >= 365
    error_message = "Retain CUR data for at least 365 days to support year-over-year billing comparison."
  }
}

# ---------------------------------------------------------------------------
# Athena
# ---------------------------------------------------------------------------

variable "athena_results_bucket_name" {
  description = "Name of the S3 bucket that stores Athena query results. Kept separate from CUR data for IAM boundary clarity."
  type        = string
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup for OpenCost queries."
  type        = string
  default     = "opencost"
}

variable "athena_bytes_scanned_cutoff" {
  description = "Maximum bytes Athena may scan per query (safety guard). Default 10 GiB."
  type        = number
  default     = 10737418240 # 10 GiB
}

variable "enable_athena_metrics" {
  description = "Publish Athena CloudWatch metrics for the workgroup."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Glue
# ---------------------------------------------------------------------------

variable "glue_database_name" {
  description = "Name of the Glue catalog database over the CUR Parquet files."
  type        = string
  default     = "cur_opencost"
}

# ---------------------------------------------------------------------------
# IAM / IRSA
# ---------------------------------------------------------------------------

variable "iam_role_name" {
  description = "Name of the IAM role OpenCost assumes via IRSA."
  type        = string
  default     = "opencost-irsa"
}

variable "eks_oidc_provider" {
  description = "EKS cluster OIDC issuer URL without the https:// prefix (e.g. 'oidc.eks.us-east-1.amazonaws.com/id/EXAMPLEABCDEF123456789')."
  type        = string
}

variable "opencost_namespace" {
  description = "Kubernetes namespace where OpenCost runs."
  type        = string
  default     = "opencost"
}

variable "opencost_service_account" {
  description = "Name of the OpenCost Kubernetes ServiceAccount that assumes the IAM role."
  type        = string
  default     = "opencost"
}

# ---------------------------------------------------------------------------
# Common
# ---------------------------------------------------------------------------

variable "tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default     = {}
}
