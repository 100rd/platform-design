output "deviceclass_h100_name" {
  description = "Name of the H100 SXM5 DeviceClass"
  value       = kubernetes_manifest.deviceclass_h100.manifest.metadata.name
}

output "deviceclass_a100_name" {
  description = "Name of the A100 80GB DeviceClass"
  value       = kubernetes_manifest.deviceclass_a100.manifest.metadata.name
}

output "claimtemplate_single_gpu_name" {
  description = "Name of the single-GPU inference ResourceClaimTemplate"
  value       = kubernetes_manifest.claimtemplate_single_gpu.manifest.metadata.name
}

output "claimtemplate_full_node_name" {
  description = "Name of the full-node training ResourceClaimTemplate"
  value       = kubernetes_manifest.claimtemplate_full_node.manifest.metadata.name
}

output "claimtemplate_prioritized_name" {
  description = "Name of the prioritized GPU inference ResourceClaimTemplate"
  value       = kubernetes_manifest.claimtemplate_prioritized.manifest.metadata.name
}
