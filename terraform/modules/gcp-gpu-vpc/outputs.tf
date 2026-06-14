output "network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "The self-link URI of the VPC network."
  value       = google_compute_network.this.self_link
}

output "subnet_name" {
  description = "The name of the subnetwork."
  value       = google_compute_subnetwork.this.name
}

output "subnet_self_link" {
  description = "The self-link URI of the subnetwork."
  value       = google_compute_subnetwork.this.self_link
}

output "subnet_cidr" {
  description = "The primary CIDR range of the subnetwork."
  value       = google_compute_subnetwork.this.ip_cidr_range
}

output "pods_secondary_range_name" {
  description = "The name of the secondary IP range used for GKE pods."
  value       = "${var.network_name}-pods"
}

output "services_secondary_range_name" {
  description = "The name of the secondary IP range used for GKE services."
  value       = "${var.network_name}-services"
}

output "router_name" {
  description = "The name of the Cloud Router."
  value       = google_compute_router.this.name
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0042 — GPU fabric network outputs (consumed by gcp-gke-gpu-nodepools / gke-gpu-fabric / gke-gpu-dranet)
# ---------------------------------------------------------------------------------------------------------------------

output "mtu" {
  description = "The MTU applied to the GPU VPC network(s)."
  value       = google_compute_network.this.mtu
}

output "data_plane_network_self_links" {
  description = "Self-links of the GPUDirect-TCPX/TCPXO data-plane networks (empty when data_plane_network_count = 0)."
  value       = google_compute_network.data_plane[*].self_link
}

output "data_plane_subnet_self_links" {
  description = "Self-links of the data-plane subnetworks, index-aligned with data_plane_network_self_links."
  value       = google_compute_subnetwork.data_plane[*].self_link
}

output "rdma_network_self_link" {
  description = "Self-link of the RoCE RDMA network, or null when enable_rdma_network = false."
  value       = var.enable_rdma_network ? google_compute_network.rdma[0].self_link : null
}

output "rdma_subnet_self_link" {
  description = "Self-link of the RDMA subnetwork, or null when enable_rdma_network = false."
  value       = var.enable_rdma_network ? google_compute_subnetwork.rdma[0].self_link : null
}
