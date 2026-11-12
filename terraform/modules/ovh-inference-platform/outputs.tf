output "models_bucket_name" {
  description = "OVHcloud Object Storage bucket name for LLM weights"
  value       = ovh_cloud_project_storage.models.name
}

output "models_bucket_virtual_host" {
  description = "S3 virtual-host URL of the OVHcloud Object Storage bucket"
  value       = ovh_cloud_project_storage.models.virtual_host
}

output "registry_url" {
  description = "OVHcloud Managed Private Registry (Harbor) URL"
  value       = var.enable_container_registry ? ovh_cloud_project_containerregistry.inference[0].url : null
}
