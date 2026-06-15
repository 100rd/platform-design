output "enabled" {
  description = "Whether the node pool module is enabled."
  value       = var.enabled
}

output "pool_name" {
  description = "Logical GPU pool name."
  value       = var.pool_name
}

output "fixed_capacity" {
  description = "Fixed number of machines in the pool (ADR-0054: no autoscaler — capacity equals the machine count)."
  value       = length(var.machines)
}

output "node_labels" {
  description = "Effective node labels (ADR-0028 + GPU-present + pool/model) the device-plugin and Volcano select on."
  value       = local.node_labels
}

output "gpu_taint" {
  description = "The GPU node taint key=value:effect applied to the pool."
  value       = "${var.gpu_taint_key}=${var.gpu_taint_value}:${var.gpu_taint_effect}"
}

output "cluster_api_managed" {
  description = "Whether Cluster-API Machine objects are managed for this pool (ADR-0054 re-image path)."
  value       = var.enabled && var.manage_cluster_api
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
