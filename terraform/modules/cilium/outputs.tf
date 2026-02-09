output "cilium_version" {
  description = "Deployed Cilium version"
  value       = var.cilium_version
}

output "hubble_enabled" {
  description = "Whether Hubble observability is enabled"
  value       = var.enable_hubble
}

output "hubble_ui_enabled" {
  description = "Whether Hubble UI is enabled"
  value       = var.enable_hubble_ui
}

output "kube_proxy_replacement" {
  description = "Whether kube-proxy is replaced by Cilium eBPF"
  value       = var.replace_kube_proxy
}

output "clustermesh_enabled" {
  description = "Whether ClusterMesh is enabled"
  value       = var.enable_clustermesh
}

output "cluster_mesh_name" {
  description = "ClusterMesh cluster name"
  value       = var.cluster_mesh_name
}

output "cluster_mesh_id" {
  description = "ClusterMesh cluster ID"
  value       = var.cluster_mesh_id
}
