output "network_names" {
  description = "Names of the Device-type Networks created for the GPUDirect data plane."
  value       = var.enabled ? [for n in var.data_plane_networks : n.name] : []
}

output "mode" {
  description = "The GPUDirect mode deployed (tcpx or tcpxo)."
  value       = var.mode
}

output "nccl_installer_image" {
  description = "The NCCL plugin installer image used for the selected mode."
  value       = local.nccl_installer_image
}
