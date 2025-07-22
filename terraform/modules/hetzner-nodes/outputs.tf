output "node_names" {
  description = "Names of the created Hetzner servers"
  value       = [for s in hcloud_server.node : s.name]
}

output "node_ips" {
  description = "Public IPv4 addresses"
  value       = [for s in hcloud_server.node : s.ipv4_address]
}
