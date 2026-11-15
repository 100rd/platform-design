output "network_id" {
  description = "STACKIT network UUID (consumed by stackit_ske_cluster)"
  value       = stackit_network.this.network_id
}

output "id" {
  description = "Terraform composite ID of the STACKIT network"
  value       = stackit_network.this.id
}

output "ipv4_prefixes" {
  description = "Allocated IPv4 CIDR prefixes of the STACKIT network"
  value       = stackit_network.this.ipv4_prefixes
}
