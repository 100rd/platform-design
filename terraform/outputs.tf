output "vpc_id" {
  description = "ID of created VPC"
  value       = module.vpc.vpc_id
}

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
}

output "hetzner_node_ips" {
  description = "Public IP addresses of Hetzner nodes"
  value       = try(module.hetzner_nodes[0].node_ips, [])
  depends_on  = [module.hetzner_nodes]
}
