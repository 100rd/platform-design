output "vpc_id" {
  description = "Scaleway VPC ID"
  value       = scaleway_vpc.this.id
}

output "private_network_id" {
  description = "Scaleway Private Network ID (regional, consumed by Kapsule)"
  value       = scaleway_vpc_private_network.this.id
}

output "private_network_name" {
  description = "Scaleway Private Network name"
  value       = scaleway_vpc_private_network.this.name
}

output "public_gateway_id" {
  description = "Scaleway VPC Public Gateway ID (if enabled)"
  value       = var.enable_public_gateway ? scaleway_vpc_public_gateway.this[0].id : null
}

output "public_gateway_ip" {
  description = "Public NAT IP address of the VPC Public Gateway (if enabled)"
  value       = var.enable_public_gateway ? scaleway_vpc_public_gateway_ip.this[0].address : null
}
