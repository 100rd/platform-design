output "models_bucket_name" {
  description = "Name of the Scaleway Object Storage bucket for model weights"
  value       = scaleway_object_bucket.models.name
}

output "models_bucket_endpoint" {
  description = "S3-compatible endpoint URL for the models bucket"
  value       = scaleway_object_bucket.models.endpoint
}

output "registry_endpoint" {
  description = "Scaleway Container Registry endpoint URL"
  value       = var.enable_container_registry ? scaleway_registry_namespace.inference[0].endpoint : null
}

output "cockpit_endpoints" {
  description = "Scaleway Cockpit push/query endpoints (metrics, logs, grafana)"
  value       = var.enable_cockpit ? scaleway_cockpit.this[0].endpoints : null
}

output "cockpit_secret_key" {
  description = "Scaleway Cockpit remote-write token secret key for VictoriaMetrics / Alloy"
  value       = var.enable_cockpit ? scaleway_cockpit_token.gpu_metrics[0].secret_key : null
  sensitive   = true
}
