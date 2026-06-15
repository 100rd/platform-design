# ---------------------------------------------------------------------------------------------------------------------
# baremetal-ml-artifact-store — Outputs (ADR-0052 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------

output "namespace" {
  description = "Kubernetes namespace where MLflow and the artifact-store credentials are deployed."
  value       = var.enabled ? kubernetes_namespace.ml_pipeline[0].metadata[0].name : var.namespace
}

output "secret_name" {
  description = "Name of the Kubernetes Secret created by ESO containing the S3 credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, MLFLOW_S3_ENDPOINT_URL)."
  value       = var.secret_name
}

output "s3_endpoint_url" {
  description = "S3-compatible endpoint URL for the artifact store. Wire into MLflow MLFLOW_S3_ENDPOINT_URL and the GH Actions ml-pipeline-baremetal.yml."
  value       = var.s3_endpoint_url
}

output "bucket_name" {
  description = "Name of the S3/MinIO/RGW bucket used as the MLflow artifact store."
  value       = var.bucket_name
}

output "backend" {
  description = "Object-store backend in use: 'minio' or 'ceph-rgw'."
  value       = var.backend
}

output "mlflow_service_account" {
  description = "Kubernetes ServiceAccount name used by MLflow pods."
  value       = var.kubernetes_service_account
}

output "platform_labels" {
  description = "ADR-0028 platform labels applied to all resources in this module."
  value       = local.platform_labels
}
