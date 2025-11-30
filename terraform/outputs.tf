# VPC Outputs
output "vpc_id" {
  description = "ID of created VPC"
  value       = module.vpc.vpc_id
}

output "vpc_private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "vpc_public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# EKS Cluster Outputs
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "Certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

# Karpenter Outputs - Required for NodePool Configuration
output "karpenter_node_iam_role_name" {
  description = "IAM role name for Karpenter-provisioned nodes (use in EC2NodeClass)"
  value       = module.eks.karpenter_node_iam_role_name
}

output "karpenter_node_iam_role_arn" {
  description = "IAM role ARN for Karpenter-provisioned nodes"
  value       = module.eks.karpenter_node_iam_role_arn
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN for Karpenter controller"
  value       = module.eks.karpenter_controller_role_arn
}

output "karpenter_queue_name" {
  description = "SQS queue name for Karpenter interruption handling"
  value       = module.eks.karpenter_queue_name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter nodes"
  value       = module.eks.karpenter_instance_profile_name
}

# Cluster Configuration for kubectl
output "cluster_name" {
  description = "Cluster name for Karpenter discovery tags (karpenter.sh/discovery)"
  value       = var.cluster_name
}

output "region" {
  description = "AWS region"
  value       = var.region
}

# Hetzner Outputs (if enabled)
output "hetzner_node_ips" {
  description = "Public IP addresses of Hetzner nodes"
  value       = try(module.hetzner_nodes[0].node_ips, [])
  depends_on  = [module.hetzner_nodes]
}

# kubectl Configuration Command
output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# NodePool Template Values
output "nodepool_template_values" {
  description = "Values for rendering NodePool templates"
  value = {
    cluster_name     = var.cluster_name
    node_role_name   = module.eks.karpenter_node_iam_role_name
    cluster_endpoint = module.eks.cluster_endpoint
    region           = var.region
    vpc_id           = module.vpc.vpc_id
  }
}
