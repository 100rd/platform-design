output "cluster_id" {
  description = "STACKIT SKE cluster composite ID"
  value       = stackit_ske_cluster.this.id
}

output "cluster_name" {
  description = "STACKIT SKE cluster name"
  value       = stackit_ske_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL parsed from SKE kubeconfig"
  value       = local.parsed_kubeconfig.clusters[0].cluster.server
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate parsed from SKE kubeconfig"
  value       = local.parsed_kubeconfig.clusters[0].cluster["certificate-authority-data"]
  sensitive   = true
}

output "client_certificate" {
  description = "Base64-encoded client certificate parsed from SKE kubeconfig"
  value       = try(local.parsed_kubeconfig.users[0].user["client-certificate-data"], "")
  sensitive   = true
}

output "client_key" {
  description = "Base64-encoded client key parsed from SKE kubeconfig"
  value       = try(local.parsed_kubeconfig.users[0].user["client-key-data"], "")
  sensitive   = true
}

output "kubeconfig_token" {
  description = "Bearer token parsed from SKE kubeconfig (if token-based auth is used)"
  value       = try(local.parsed_kubeconfig.users[0].user.token, "")
  sensitive   = true
}
