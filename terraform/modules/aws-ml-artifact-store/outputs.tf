# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-artifact-store — Outputs (ADR-0048 D2 / WS-B)
#
# Mirror of ml-artifact-store (GCS) outputs so the two artifact stores stay diff-able.
# All outputs return empty string when create_resources = false (plan-only runs).
# ---------------------------------------------------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket used as the MLflow artifact store."
  value       = length(aws_s3_bucket.mlflow_artifacts) > 0 ? aws_s3_bucket.mlflow_artifacts[0].id : ""
}

output "bucket_arn" {
  description = "ARN of the MLflow artifact store S3 bucket."
  value       = length(aws_s3_bucket.mlflow_artifacts) > 0 ? aws_s3_bucket.mlflow_artifacts[0].arn : ""
}

output "bucket_url" {
  description = "s3:// URI for use as MLFLOW_DEFAULT_ARTIFACT_ROOT in values.yaml. Mirrors the gs:// output from ml-artifact-store (GCS)."
  value       = length(aws_s3_bucket.mlflow_artifacts) > 0 ? "s3://${aws_s3_bucket.mlflow_artifacts[0].id}" : ""
}

output "mlflow_pod_identity_role_arn" {
  description = "ARN of the IAM role for MLflow EKS Pod Identity. Annotate the mlflow Kubernetes ServiceAccount with this ARN per ADR-0018."
  value       = length(aws_iam_role.mlflow_artifact_store) > 0 ? aws_iam_role.mlflow_artifact_store[0].arn : ""
}

output "mlflow_pod_identity_role_name" {
  description = "Name of the IAM role for MLflow EKS Pod Identity."
  value       = length(aws_iam_role.mlflow_artifact_store) > 0 ? aws_iam_role.mlflow_artifact_store[0].name : ""
}
