# outputs.tf for the EKS Agent Cluster module

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster's Kubernetes API."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "The base64 encoded certificate data for the EKS cluster's Kubernetes API."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The OIDC issuer URL for the EKS cluster."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster, used for IRSA."
  value       = module.eks.oidc_provider_arn
}

output "cluster_primary_security_group_id" {
  description = "The ID of the cluster's primary security group."
  value       = module.eks.cluster_primary_security_group_id
}
