output "enabled" {
  description = "Whether GPU NodePools were created by this module."
  value       = var.enabled
}

output "nodepool_names" {
  description = "Names of the GPU NodePools created (empty when disabled)."
  value       = var.enabled ? module.karpenter_nodepools.nodepool_names : []
}

output "ec2_nodeclass_names" {
  description = "Names of the EC2NodeClasses created (empty when disabled)."
  value       = var.enabled ? module.karpenter_nodepools.ec2_nodeclass_names : []
}

output "efa_pools" {
  description = "Pool names that have EFA enabled (device-plugin mode under Karpenter, ADR-0045 D2)."
  value       = [for name, cfg in var.gpu_pools : name if cfg.enable_efa]
}

output "platform_tags" {
  description = "Effective ADR-0028 node tags."
  value       = local.platform_tags
}
