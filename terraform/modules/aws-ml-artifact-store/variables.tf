# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-artifact-store — Variables (ADR-0048 D2 / WS-B)
#
# AWS mirror of terraform/modules/ml-artifact-store (GCS) — field-for-field parity
# where it makes sense so the two clouds' artifact stores stay diff-able.
# GCS lifecycle ladder: Nearline→Coldline→Delete → S3 analog: STANDARD-IA→Glacier→Expire.
# ---------------------------------------------------------------------------------------------------------------------

variable "bucket_name" {
  description = "Name of the S3 bucket used as the MLflow artifact store. Must be globally unique."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the S3 bucket is created. Defaults to the provider region."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for SSE-KMS bucket encryption (ADR-0048 D2). Leave empty to use the AWS-managed S3 key (aws/s3), which is acceptable for non-prod."
  type        = string
  default     = ""
}

variable "versioning_enabled" {
  description = "Enable S3 object versioning. Keep true in all envs for SOC2 artifact audit trail (ADR-0048 D2 / ADR-0037 D2 requirement)."
  type        = bool
  default     = true
}

# -------------------------------------------------------------------------
# Lifecycle transitions (S3 analog of GCS Nearline->Coldline->Delete)
# -------------------------------------------------------------------------

variable "standard_ia_after_days" {
  description = "Age (days) after which objects transition to STANDARD-IA storage class (the S3 analog of GCS Nearline). 0 = disabled."
  type        = number
  default     = 90

  validation {
    condition     = var.standard_ia_after_days >= 0
    error_message = "standard_ia_after_days must be >= 0."
  }
}

variable "glacier_after_days" {
  description = "Age (days) after which objects transition to Glacier Instant Retrieval (the S3 analog of GCS Coldline). Must be > standard_ia_after_days when both are non-zero. 0 = disabled."
  type        = number
  default     = 365

  validation {
    condition     = var.glacier_after_days >= 0
    error_message = "glacier_after_days must be >= 0."
  }
}

variable "expire_after_days" {
  description = "Age (days) after which objects are permanently deleted (the S3 analog of GCS deletion_after_days). Must be > glacier_after_days when both are non-zero. 0 = disabled."
  type        = number
  default     = 730

  validation {
    condition     = var.expire_after_days >= 0
    error_message = "expire_after_days must be >= 0."
  }
}

# -------------------------------------------------------------------------
# Pod Identity + ABAC (ADR-0018, ADR-0048 D2)
# -------------------------------------------------------------------------

variable "mlflow_pod_identity_role_name" {
  description = "Name of the IAM role created for MLflow EKS Pod Identity. The role grants S3 object read/write scoped to this bucket only with the ABAC condition (ADR-0018 / ADR-0048 D2)."
  type        = string
  default     = "mlflow-artifact-store"
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster hosting MLflow. Used to scope the Pod Identity trust policy to the EKS service principal for this cluster."
  type        = string
}

variable "mlflow_kubernetes_namespace" {
  description = "Kubernetes namespace where the MLflow pod runs. Used in the Pod Identity trust policy condition."
  type        = string
  default     = "ml-pipeline"
}

variable "mlflow_kubernetes_service_account" {
  description = "Kubernetes ServiceAccount name for MLflow. Used in the Pod Identity trust policy condition."
  type        = string
  default     = "mlflow"
}

# -------------------------------------------------------------------------
# Apply gate — plan section constraint 3 (apply-gated)
# Default false ensures no real AWS resources are created when plan runs
# from a feature branch or in CI without explicit approval.
# -------------------------------------------------------------------------

variable "create_resources" {
  description = "Master apply-gate toggle. Set to true to create the S3 bucket, KMS alias, and IAM role. Defaults to false so terraform plan runs safely from feature branches without creating real AWS resources."
  type        = bool
  default     = false
}

# -------------------------------------------------------------------------
# ADR-0028 tags — AWS-plane spelling (colon key: platform:system)
# AWS tags allow ':' in keys; use the canonical ADR-0028 colon form.
# The ABAC condition in the IAM policy uses:
#   aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system
# so both the IAM role and the S3 bucket MUST carry this tag.
# -------------------------------------------------------------------------

variable "tags" {
  description = <<-EOT
    ADR-0028 platform tags applied to every AWS resource in this module.
    Required keys: platform:system, platform:component, platform:env,
    platform:owner, platform:managed-by.
    Both the IAM role and the S3 bucket carry platform:system so the ABAC
    condition can fire (aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system).
  EOT
  type        = map(string)
  default = {
    "platform:system"     = "ml-pipeline"
    "platform:component"  = "model-registry"
    "platform:env"        = "staging"
    "platform:owner"      = "team-ml"
    "platform:managed-by" = "terragrunt"
  }
}
