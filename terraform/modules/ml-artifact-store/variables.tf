# ---------------------------------------------------------------------------------------------------------------------
# ml-artifact-store — Variables (ADR-0037 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID that owns the GCS bucket and the Google Service Account."
  type        = string
}

variable "bucket_name" {
  description = "Name of the GCS bucket used as the MLflow artifact store. Must be globally unique."
  type        = string
}

variable "location" {
  description = "GCS bucket location. Use a multi-region (e.g. 'US', 'EU') for prod; a region (e.g. 'us-central1') for dev/staging."
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Default storage class for the bucket. MULTI_REGIONAL for prod; STANDARD for dev/staging."
  type        = string
  default     = "MULTI_REGIONAL"

  validation {
    condition     = contains(["MULTI_REGIONAL", "DUAL_REGIONAL", "REGIONAL", "STANDARD", "NEARLINE", "COLDLINE"], var.storage_class)
    error_message = "storage_class must be one of MULTI_REGIONAL, DUAL_REGIONAL, REGIONAL, STANDARD, NEARLINE, COLDLINE."
  }
}

variable "versioning_enabled" {
  description = "Enable GCS object versioning. Keep true in all envs for artifact audit trail (SOC2 requirement, ADR-0037 D2)."
  type        = bool
  default     = true
}

# -------------------------------------------------------------------------
# Lifecycle transitions
# -------------------------------------------------------------------------
variable "nearline_after_days" {
  description = "Age (days) after which objects transition to Nearline storage. 0 = disabled."
  type        = number
  default     = 90

  validation {
    condition     = var.nearline_after_days >= 0
    error_message = "nearline_after_days must be >= 0."
  }
}

variable "coldline_after_days" {
  description = "Age (days) after which objects transition to Coldline storage. 0 = disabled."
  type        = number
  default     = 365

  validation {
    condition     = var.coldline_after_days >= 0
    error_message = "coldline_after_days must be >= 0."
  }
}

variable "deletion_after_days" {
  description = "Age (days) after which objects are deleted permanently. 0 = disabled."
  type        = number
  default     = 730

  validation {
    condition     = var.deletion_after_days >= 0
    error_message = "deletion_after_days must be >= 0."
  }
}

# -------------------------------------------------------------------------
# Workload Identity
# -------------------------------------------------------------------------
variable "workload_identity_sa_name" {
  description = "Short name of the Google Service Account created for MLflow Workload Identity."
  type        = string
  default     = "mlflow-artifact-store"
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace where the MLflow pod runs. Used in Workload Identity member binding."
  type        = string
  default     = "ml-pipeline"
}

variable "kubernetes_service_account" {
  description = "Kubernetes ServiceAccount name for MLflow. Used in Workload Identity member binding."
  type        = string
  default     = "mlflow"
}

# -------------------------------------------------------------------------
# ADR-0028 labels — GCP-plane spelling (underscore separator, no colons)
# GCP label keys use underscores (platform_system), not colons, because GCP
# labels disallow ':'. This is the canonical GCP-plane spelling of ADR-0028.
# -------------------------------------------------------------------------
variable "labels" {
  description = <<-EOT
    ADR-0028 platform labels applied to the GCS bucket and GSA.
    Required keys: platform_system, platform_component, platform_env,
    platform_owner, platform_managed_by.
  EOT
  type        = map(string)
  default = {
    platform_system     = "ml-pipeline"
    platform_component  = "model-registry"
    platform_env        = "staging"
    platform_owner      = "team-ml"
    platform_managed_by = "terragrunt"
  }
}
