# ---------------------------------------------------------------------------------------------------------------------
# ml-artifact-store (ADR-0037 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------
# GCS bucket for MLflow artifact storage + Google Service Account with
# Workload Identity binding so MLflow pods authenticate via GKE metadata
# without static JSON keys.
#
# Resources:
#   - google_storage_bucket              (uniform bucket-level access, versioning,
#                                         lifecycle rules, ADR-0028 labels)
#   - google_service_account             (GSA for MLflow Workload Identity)
#   - google_storage_bucket_iam_member   (roles/storage.objectAdmin on bucket only)
#   - google_service_account_iam_member  (roles/iam.workloadIdentityUser for KSA)
#
# ADR-0028: GCS labels use underscore keys (platform_system) — GCP disallows ':'.
# The K8s-plane dotted keys (platform.system) live in values.yaml / ArgoCD apps.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ADR-0028 baseline labels merged with caller overrides.
  platform_labels = merge(
    {
      platform_system     = "ml-pipeline"
      platform_component  = "model-registry"
      platform_managed_by = "terragrunt"
    },
    var.labels,
  )
}

# ---------------------------------------------------------------------------------------------------------------------
# GCS Bucket — uniform bucket-level access (IAM-only), versioning, lifecycle
# ---------------------------------------------------------------------------------------------------------------------

resource "google_storage_bucket" "mlflow_artifacts" {
  name          = var.bucket_name
  project       = var.project_id
  location      = var.location
  storage_class = var.storage_class

  # Uniform bucket-level access — no per-object ACLs (ADR-0037 D2)
  uniform_bucket_level_access = true

  # Object versioning — SOC2 reproducibility audit trail (ADR-0037 D2)
  versioning {
    enabled = var.versioning_enabled
  }

  # Nearline transition
  dynamic "lifecycle_rule" {
    for_each = var.nearline_after_days > 0 ? [1] : []

    content {
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition {
        age = var.nearline_after_days
      }
    }
  }

  # Coldline transition
  dynamic "lifecycle_rule" {
    for_each = var.coldline_after_days > 0 ? [1] : []

    content {
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition {
        age = var.coldline_after_days
      }
    }
  }

  # Permanent deletion
  dynamic "lifecycle_rule" {
    for_each = var.deletion_after_days > 0 ? [1] : []

    content {
      action {
        type = "Delete"
      }
      condition {
        age = var.deletion_after_days
      }
    }
  }

  # ADR-0028 labels (GCP-plane underscore spelling)
  labels = local.platform_labels

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Google Service Account — MLflow Workload Identity
# GKE metadata server provides OIDC token; no static JSON key is created.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_service_account" "mlflow" {
  account_id   = var.workload_identity_sa_name
  display_name = "MLflow Artifact Store — Workload Identity SA (ADR-0037)"
  project      = var.project_id
}

# Bucket-scoped IAM — objectAdmin on THIS bucket only (not project-wide storage).
resource "google_storage_bucket_iam_member" "mlflow_object_admin" {
  bucket = google_storage_bucket.mlflow_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mlflow.email}"
}

# Workload Identity binding — GKE KSA impersonates the GSA.
# Format: serviceAccount:{project}.svc.id.goog[{namespace}/{ksa_name}]
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.mlflow.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}
