output "tgw_connect_peer_ids" {
  description = "Map of TGW Connect peer IDs"
  value       = { for k, v in aws_ec2_transit_gateway_connect_peer.this : k => v.id }
}

output "bgp_asn" {
  description = "BGP ASN configured for the cluster"
  value       = try(values(aws_ec2_transit_gateway_connect_peer.this)[0].bgp_asn, null)
}

output "peer_addresses" {
  description = "Map of peer addresses by AZ"
  value       = { for k, v in aws_ec2_transit_gateway_connect_peer.this : k => v.peer_address }
}
