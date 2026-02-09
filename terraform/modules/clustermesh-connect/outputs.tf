output "connected_clusters" {
  description = "List of remote cluster names connected via ClusterMesh"
  value       = [for name, _ in var.remote_clusters : name]
}
