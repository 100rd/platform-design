output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

# Karpenter outputs
output "karpenter_queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling"
  value       = module.karpenter.queue_name
}

output "karpenter_node_iam_role_name" {
  description = "IAM role name for Karpenter nodes"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN for Karpenter nodes"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter nodes"
  value       = module.karpenter.instance_profile_name
}
