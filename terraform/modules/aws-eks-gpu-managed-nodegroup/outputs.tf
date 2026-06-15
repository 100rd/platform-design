output "enabled" {
  description = "Whether the reserved training node group was created."
  value       = var.enabled
}

output "node_group_name" {
  description = "Name of the managed node group (null when disabled)."
  value       = var.enabled ? aws_eks_node_group.training[0].node_group_name : null
}

output "node_role_arn" {
  description = "IAM role ARN used by the node group (null when disabled)."
  value       = var.enabled ? (var.node_role_arn != "" ? var.node_role_arn : aws_iam_role.node[0].arn) : null
}

output "capacity_block_reservation_id" {
  description = "Capacity Block reservation ID wired to the node group (ADR-0046 D4)."
  value       = var.capacity_block_reservation_id
}

output "efa_mode" {
  description = "EFA exposure mode (dra on managed node groups, ADR-0045 D3)."
  value       = var.efa_mode
}

output "platform_tags" {
  description = "Effective ADR-0028 tags."
  value       = local.base_tags
}
