# ---------------------------------------------------------------------------------------------------------------------
# Tests for the ml-artifact-store module (ADR-0037 / WS-B)
# google provider is mocked so no real GCP credentials are needed.
# All runs use command = plan (no real GCS bucket is created).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "google" {
  # Realistic GSA email so IAM member expressions render validly.
  override_resource {
    target = google_service_account.mlflow
    values = {
      email = "mlflow-artifact-store@ml-pipeline-test-123.iam.gserviceaccount.com"
      name  = "projects/ml-pipeline-test-123/serviceAccounts/mlflow-artifact-store@ml-pipeline-test-123.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target = google_storage_bucket.mlflow_artifacts
    values = {
      name = "mlflow-artifacts-staging-ml-pipeline-test-123"
    }
  }
}

variables {
  project_id  = "ml-pipeline-test-123"
  bucket_name = "mlflow-artifacts-staging-ml-pipeline-test-123"
  labels = {
    platform_system     = "ml-pipeline"
    platform_component  = "model-registry"
    platform_env        = "test"
    platform_owner      = "team-ml"
    platform_managed_by = "terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Bucket configuration
# ---------------------------------------------------------------------------------------------------------------------

run "bucket_has_uniform_access" {
  command = plan

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.uniform_bucket_level_access == true
    error_message = "Bucket must use uniform bucket-level access (IAM-only; no per-object ACLs)."
  }
}

run "bucket_versioning_enabled_by_default" {
  command = plan

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.versioning[0].enabled == true
    error_message = "Object versioning must be enabled by default for SOC2 reproducibility audit trail."
  }
}

run "bucket_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.labels["platform_system"] == "ml-pipeline"
    error_message = "Bucket must carry platform_system = ml-pipeline per ADR-0028."
  }

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.labels["platform_component"] == "model-registry"
    error_message = "Bucket must carry platform_component = model-registry per ADR-0028."
  }

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.labels["platform_env"] == "test"
    error_message = "Caller-supplied platform_env must be merged onto the bucket."
  }
}

run "lifecycle_nearline_default_90_days" {
  command = plan

  assert {
    condition     = var.nearline_after_days == 90
    error_message = "Default nearline_after_days should be 90."
  }
}

run "lifecycle_deletion_default_730_days" {
  command = plan

  assert {
    condition     = var.deletion_after_days == 730
    error_message = "Default deletion_after_days should be 730."
  }
}

run "versioning_can_be_disabled" {
  command = plan

  variables {
    versioning_enabled = false
  }

  assert {
    condition     = google_storage_bucket.mlflow_artifacts.versioning[0].enabled == false
    error_message = "Versioning should be disabled when versioning_enabled = false."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM / Workload Identity
# ---------------------------------------------------------------------------------------------------------------------

run "object_admin_scoped_to_bucket" {
  command = plan

  assert {
    condition     = google_storage_bucket_iam_member.mlflow_object_admin.role == "roles/storage.objectAdmin"
    error_message = "MLflow GSA must be granted roles/storage.objectAdmin on the artifact bucket."
  }

  assert {
    condition     = google_storage_bucket_iam_member.mlflow_object_admin.bucket == var.bucket_name
    error_message = "IAM binding must target the ml-artifact-store bucket, not a wildcard."
  }
}

run "workload_identity_role_is_wi_user" {
  command = plan

  assert {
    condition     = google_service_account_iam_member.workload_identity_binding.role == "roles/iam.workloadIdentityUser"
    error_message = "Workload Identity binding must use roles/iam.workloadIdentityUser."
  }
}

run "workload_identity_member_format" {
  command = plan

  assert {
    condition = can(regex(
      "^serviceAccount:[a-z0-9-]+\\.svc\\.id\\.goog\\[.+/.+\\]$",
      google_service_account_iam_member.workload_identity_binding.member,
    ))
    error_message = "Workload Identity member must match format serviceAccount:{project}.svc.id.goog[{ns}/{ksa}]."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------------------------------------------------

run "output_bucket_url_has_gs_prefix" {
  command = plan

  assert {
    condition     = startswith(output.bucket_url, "gs://")
    error_message = "bucket_url output must start with gs:// for use as MLFLOW_DEFAULT_ARTIFACT_ROOT."
  }
}

run "rejects_invalid_storage_class" {
  command = plan

  variables {
    storage_class = "INVALID_CLASS"
  }

  expect_failures = [
    var.storage_class,
  ]
}
