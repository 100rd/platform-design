output "enabled" {
  description = "Whether the GPU VPC was provisioned by this module."
  value       = var.enabled
}

output "vpc_id" {
  description = "ID of the GPU VPC (null when disabled)."
  value       = var.enabled ? module.vpc[0].vpc_id : null
}

output "private_subnet_ids" {
  description = "Private (control-plane / general) subnet IDs (empty when disabled)."
  value       = var.enabled ? module.vpc[0].private_subnets : []
}

output "gpu_subnet_ids" {
  description = "GPU/EFA interconnect subnet IDs (modeled as intra subnets; empty when disabled)."
  value       = var.enabled ? module.vpc[0].intra_subnets : []
}

output "efa_gpu_subnet_id" {
  description = "The single GPU subnet EFA pools pin to when single_az_gpu_subnet = true (null when disabled or no GPU subnets)."
  value       = var.enabled && var.single_az_gpu_subnet && length(var.gpu_subnets) > 0 ? module.vpc[0].intra_subnets[0] : null
}

output "efa_security_group_id" {
  description = "ID of the self-referencing EFA security group (null when disabled or not created)."
  value       = var.enabled && var.enable_efa_security_group ? aws_security_group.efa[0].id : null
}

output "mtu" {
  description = "Jumbo-frame MTU set on the GPU subnets (ADR-0045 D1)."
  value       = var.mtu
}

output "platform_tags" {
  description = "Effective ADR-0028 tags applied to the VPC resources."
  value       = local.base_tags
}
