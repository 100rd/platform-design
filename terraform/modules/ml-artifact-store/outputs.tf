# ---------------------------------------------------------------------------------------------------------------------
# ml-artifact-store — Outputs (ADR-0037 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the GCS bucket used as the MLflow artifact store."
  value       = google_storage_bucket.mlflow_artifacts.name
}

output "bucket_url" {
  description = "gs:// URI for use as MLFLOW_DEFAULT_ARTIFACT_ROOT in values.yaml."
  value       = "gs://${google_storage_bucket.mlflow_artifacts.name}"
}

output "gsa_email" {
  description = "Email of the Google SA to set on the MLflow K8s ServiceAccount annotation (iam.gke.io/gcp-service-account)."
  value       = google_service_account.mlflow.email
}

output "gsa_name" {
  description = "Full resource name of the GSA (for IAM policy references)."
  value       = google_service_account.mlflow.name
}

output "workload_identity_member" {
  description = "IAM member string for the Workload Identity binding (useful for debugging)."
  value       = "serviceAccount:${var.project_id}.svc.id.goog[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}
