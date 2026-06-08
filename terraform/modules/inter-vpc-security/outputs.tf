# ---------------------------------------------------------------------------------------------------------------------
# Inter-VPC Access Security — outputs (ADR-0013)
# ---------------------------------------------------------------------------------------------------------------------

output "network_vpn_route_table_id" {
  description = "ID of the isolated Network VPN TGW route table. Null when enable_vpn_routing = false."
  value       = var.enable_vpn_routing ? aws_ec2_transit_gateway_route_table.network_vpn[0].id : null
}

output "vpn_forward_route_keys" {
  description = "Keys of the VPN outbound allow-list forward routes that were created."
  value       = keys(aws_ec2_transit_gateway_route.vpn_forward)
}

output "vpn_return_route_keys" {
  description = "Keys of the VPN return routes that were created on spoke route tables."
  value       = keys(aws_ec2_transit_gateway_route.vpn_return)
}

output "prod_nacl_backstop_enabled" {
  description = "Whether the prod NACL backstop (deny standard sub-pool) is applied."
  value       = var.enable_prod_nacl_backstop
}

output "prod_nacl_backstop_subnet_count" {
  description = "Number of prod subnet NACLs the backstop rules were applied to."
  value       = var.enable_prod_nacl_backstop ? length(var.prod_subnet_nacl_ids) : 0
}
