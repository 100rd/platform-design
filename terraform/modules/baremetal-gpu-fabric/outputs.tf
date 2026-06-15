output "enabled" {
  description = "Whether the GPU fabric was deployed."
  value       = var.enabled
}

output "fabric_path" {
  description = "Active day-0 fabric path (sriov, ADR-0053 day-0 primary)."
  value       = var.fabric_path
}

output "fabric_mode" {
  description = "Physical fabric mode (infiniband / roce)."
  value       = var.fabric_mode
}

output "dranet_enabled" {
  description = "Whether the gated DRANET (Cilium netdev DRA) target path is enabled (ADR-0053 D3 maturity gate)."
  value       = var.enabled && var.enable_dranet
}

output "sriov_resource_name" {
  description = "Device-plugin resource name pods request RDMA VFs as."
  value       = var.sriov_resource_name
}

output "mtu" {
  description = "Fabric MTU (9000 jumbo frames)."
  value       = var.mtu
}

output "platform_labels" {
  description = "Effective ADR-0028 dotted labels."
  value       = local.platform_labels
}
