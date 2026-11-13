output "models_bucket_name" {
  description = "STACKIT Object Storage bucket name for LLM weights"
  value       = stackit_objectstorage_bucket.models.name
}

output "models_bucket_url_path_style" {
  description = "Path-style S3 URL of the STACKIT Object Storage bucket"
  value       = stackit_objectstorage_bucket.models.url_path_style
}

output "models_bucket_url_virtual_hosted_style" {
  description = "Virtual-hosted S3 URL of the STACKIT Object Storage bucket"
  value       = stackit_objectstorage_bucket.models.url_virtual_hosted_style
}

output "observability_instance_id" {
  description = "STACKIT Observability (Argus) instance UUID (linked to SKE extensions.observability)"
  value       = var.enable_observability ? stackit_observability_instance.this[0].instance_id : null
}

output "observability_grafana_url" {
  description = "Managed Grafana dashboard URL of the STACKIT Observability instance"
  value       = var.enable_observability ? stackit_observability_instance.this[0].grafana_url : null
}
