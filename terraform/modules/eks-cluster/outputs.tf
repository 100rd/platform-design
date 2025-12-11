output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Security group ids attached to the node group"
  value       = module.eks.node_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enable_irsa = true"
  value       = module.eks.oidc_provider_arn
}

output "dns_sync_role_arn" {
  description = "IAM Role ARN for DNS Sync service account"
  value       = module.dns_sync_irsa.iam_role_arn
}

output "failover_controller_role_arn" {
  description = "IAM Role ARN for Failover Controller service account"
  value       = module.failover_controller_irsa.iam_role_arn
}
