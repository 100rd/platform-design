output "cluster_id" {
  description = "OVHcloud MKS cluster ID"
  value       = ovh_cloud_project_kube.this.id
}

output "cluster_name" {
  description = "OVHcloud MKS cluster name"
  value       = ovh_cloud_project_kube.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = ovh_cloud_project_kube.this.kubeconfig_attributes[0].host
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  value       = ovh_cloud_project_kube.this.kubeconfig_attributes[0].cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Base64-encoded client certificate"
  value       = ovh_cloud_project_kube.this.kubeconfig_attributes[0].client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client key"
  value       = ovh_cloud_project_kube.this.kubeconfig_attributes[0].client_key
  sensitive   = true
}

output "gpu_pool_ids" {
  description = "Map of GPU node pool names to their OVH MKS nodepool IDs"
  value       = { for k, v in ovh_cloud_project_kube_nodepool.gpu : k => v.id }
}
