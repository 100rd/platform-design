output "connected_clusters" {
  description = "List of remote cluster names connected via ClusterMesh (literal + Secrets-Manager-resolved)."
  value       = keys(local.all_remotes)
}
