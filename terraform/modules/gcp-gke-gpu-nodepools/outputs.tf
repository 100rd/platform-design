output "node_pool_names" {
  description = "Map of node pool keys to their names."
  value       = { for k, v in google_container_node_pool.this : k => v.name }
}

output "node_pool_ids" {
  description = "Map of node pool keys to their full resource IDs."
  value       = { for k, v in google_container_node_pool.this : k => v.id }
}
