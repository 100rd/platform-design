# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU VPC Module
# ---------------------------------------------------------------------------------------------------------------------
# Creates a custom-mode VPC with a primary subnet (including secondary ranges for
# GKE pods and services), a Cloud Router, and a Cloud NAT gateway.
#
# Designed for GPU analysis GKE clusters that require private Google API access,
# outbound NAT for pulling container images, and properly sized secondary ranges
# for pod and service networking.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# VPC Network
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_network" "this" {
  project = var.project_id
  name    = var.network_name

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Custom VPC for GPU analysis workloads in ${var.environment}"
}

# ---------------------------------------------------------------------------------------------------------------------
# Subnetwork with secondary ranges for GKE pods and services
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_subnetwork" "this" {
  project = var.project_id
  name    = "${var.network_name}-subnet"
  region  = var.region
  network = google_compute_network.this.id

  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  # Secondary range for GKE pods — /18 from a /16 primary
  # cidrsubnet("10.200.0.0/16", 2, 1) = "10.200.64.0/18"
  secondary_ip_range {
    range_name    = "${var.network_name}-pods"
    ip_cidr_range = cidrsubnet(var.subnet_cidr, 2, 1)
  }

  # Secondary range for GKE services — /22 from a /16 primary
  # cidrsubnet("10.200.0.0/16", 6, 16) = "10.200.4.0/22"
  secondary_ip_range {
    range_name    = "${var.network_name}-services"
    ip_cidr_range = cidrsubnet(var.subnet_cidr, 6, 16)
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Cloud Router — required for Cloud NAT
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.this.id

  bgp {
    asn = 64514
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Cloud NAT — outbound internet for private GKE nodes (image pulls, etc.)
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_router_nat" "this" {
  project = var.project_id
  name    = "${var.network_name}-nat"
  region  = var.region
  router  = google_compute_router.this.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.this.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
