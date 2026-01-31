output "vpn_connection_ids" {
  description = "Map of VPN connection name to VPN connection ID"
  value       = { for k, v in aws_vpn_connection.this : k => v.id }
}

output "customer_gateway_ids" {
  description = "Map of customer gateway name to ID"
  value       = { for k, v in aws_customer_gateway.this : k => v.id }
}

output "tunnel_details" {
  description = "Map of VPN name to tunnel endpoint details"
  sensitive   = true
  value = { for k, v in aws_vpn_connection.this : k => {
    tunnel1_address    = v.tunnel1_address
    tunnel2_address    = v.tunnel2_address
    tunnel1_cgw_inside = v.tunnel1_cgw_inside_address
    tunnel2_cgw_inside = v.tunnel2_cgw_inside_address
  }}
}
