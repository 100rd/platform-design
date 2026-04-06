# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference VPC — Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "intra_subnet_ids" {
  description = "List of intra subnet IDs (GPU interconnect)"
  value       = module.vpc.intra_subnets
}

output "intra_route_table_ids" {
  description = "List of intra route table IDs"
  value       = module.vpc.intra_route_table_ids
}

output "nat_gateway_ids" {
  description = "List of NAT gateway IDs"
  value       = module.vpc.natgw_ids
}

output "tgw_connect_attachment_id" {
  description = "Transit Gateway Connect attachment ID"
  value       = try(aws_ec2_transit_gateway_connect.this[0].id, "")
}

output "tgw_vpc_attachment_id" {
  description = "Transit Gateway VPC attachment ID"
  value       = try(aws_ec2_transit_gateway_vpc_attachment.this[0].id, "")
}

output "pod_cidr" {
  description = "Pod CIDR block (announced via BGP, not part of VPC CIDR)"
  value       = var.pod_cidr
}

output "gpu_interconnect_security_group_id" {
  description = "Security group ID for GPU node-to-node communication"
  value       = aws_security_group.gpu_interconnect.id
}

output "bgp_gre_security_group_id" {
  description = "Security group ID for BGP and GRE (TGW Connect peering)"
  value       = aws_security_group.bgp_gre.id
}
