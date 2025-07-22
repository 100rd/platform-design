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

output "node_group_role_arn" {
  description = "Node group IAM role ARN"
  value       = module.eks.node_group_iam_role_arns
}
