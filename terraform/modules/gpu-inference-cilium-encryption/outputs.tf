output "encryption_config_name" {
  description = "Name of the encryption configuration ConfigMap"
  value       = kubernetes_config_map_v1.cilium_encryption_config.metadata[0].name
}

output "encryption_type" {
  description = "Type of encryption configured"
  value       = "wireguard"
}

output "operator_replicas" {
  description = "Number of Cilium operator replicas"
  value       = var.operator_replicas
}
