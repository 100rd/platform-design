output "enabled" {
  description = "Whether the EKS GPU cluster was provisioned by this module."
  value       = var.enabled
}

output "cluster_name" {
  description = "Name of the EKS GPU cluster (echoes input even when disabled, for downstream wiring)."
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint (null when disabled)."
  value       = var.enabled ? module.eks[0].cluster_endpoint : null
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA data for the EKS cluster (null when disabled)."
  value       = var.enabled ? module.eks[0].cluster_certificate_authority_data : null
}

output "cluster_version" {
  description = "Kubernetes version of the cluster (>= 1.33 for DRA, ADR-0044 D2)."
  value       = var.cluster_version
}

output "node_security_group_id" {
  description = "Security group ID of the cluster node group (null when disabled)."
  value       = var.enabled ? module.eks[0].node_security_group_id : null
}

output "oidc_provider_arn" {
  description = "IRSA/OIDC provider ARN (null when disabled)."
  value       = var.enabled ? module.eks[0].oidc_provider_arn : null
}

output "platform_tags" {
  description = "Effective ADR-0028 tags applied to the cluster."
  value       = local.base_tags
}
