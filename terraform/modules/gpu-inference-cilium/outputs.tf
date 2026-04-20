output "cilium_version" {
  description = "Installed Cilium version"
  value       = helm_release.cilium.version
}

output "cilium_namespace" {
  description = "Namespace where Cilium is installed"
  value       = helm_release.cilium.namespace
}

output "pod_cidr" {
  description = "Pod CIDR configured for Cilium cluster-pool IPAM"
  value       = var.pod_cidr
}

output "bgp_local_asn" {
  description = "Local ASN used for BGP peering"
  value       = var.bgp_local_asn
}

output "cluster_mesh_name" {
  description = "Cluster name registered in ClusterMesh"
  value       = var.cluster_mesh_name
}

output "cluster_mesh_id" {
  description = "Numeric cluster ID registered in ClusterMesh"
  value       = var.cluster_mesh_id
}

output "clustermesh_enabled" {
  description = "Whether ClusterMesh is enabled on this cluster"
  value       = var.enable_clustermesh
}

output "dsr_enabled" {
  description = "Whether Direct Server Return is enabled"
  value       = var.enable_dsr
}

output "xdp_enabled" {
  description = "Whether XDP native acceleration is enabled"
  value       = var.enable_xdp
}

output "sockops_enabled" {
  description = "Whether socket-level load balancing is enabled"
  value       = var.enable_sockops
}
