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
