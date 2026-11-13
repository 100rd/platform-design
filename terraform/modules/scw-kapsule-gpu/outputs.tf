output "cluster_id" {
  description = "Scaleway Kapsule cluster ID"
  value       = scaleway_k8s_cluster.this.id
}

output "cluster_name" {
  description = "Scaleway Kapsule cluster name"
  value       = scaleway_k8s_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = scaleway_k8s_cluster.this.apiserver_url
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate from kubeconfig"
  value       = scaleway_k8s_cluster.this.kubeconfig[0].cluster_ca_certificate
  sensitive   = true
}

output "kubeconfig_token" {
  description = "Admin bearer token from kubeconfig for Helm/Kubernetes provider auth"
  value       = scaleway_k8s_cluster.this.kubeconfig[0].token
  sensitive   = true
}

output "gpu_pool_ids" {
  description = "Map of GPU node pool names to their Scaleway pool IDs"
  value       = { for k, v in scaleway_k8s_pool.gpu : k => v.id }
}
