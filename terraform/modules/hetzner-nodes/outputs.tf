output "node_names" {
  description = "Names of the created Hetzner servers"
  value       = [for s in hcloud_server.node : s.name]
}
