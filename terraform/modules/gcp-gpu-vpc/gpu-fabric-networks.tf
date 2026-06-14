# ---------------------------------------------------------------------------------------------------------------------
# GPU high-performance fabric networks (ADR-0042 D2/D3)
# ---------------------------------------------------------------------------------------------------------------------
# Optional data-plane and RDMA networks that carry GPU↔GPU traffic, kept separate from
# the primary (control/pod) VPC above. All run at the jumbo MTU (var.mtu, default 8896)
# and are intended to be attached to GPU node pools as additional NICs.
#
#   * Data-plane networks (var.data_plane_network_count): the GPUDirect-TCPX/TCPXO path
#     for H100 / H100-Mega (a3-highgpu-8g needs 4, a3-megagpu-8g needs 8). Each is an
#     independent VPC + /24 subnet consumed via the node pool's additional networks and
#     wired with GKENetworkParamSet by the gke-gpu-fabric module.
#
#   * RDMA network (var.enable_rdma_network): the GPUDirect-RDMA / RoCE path for
#     H200 / B200 (a3-ultragpu-8g, a4-highgpu-8g). Created with the RoCE network_profile
#     and consumed by GKE managed DRANET (gke-gpu-dranet module).
#
# Both default to off so existing single-VPC deployments are unchanged.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Data-plane networks — GPUDirect-TCPX/TCPXO (H100 / H100-Mega)
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_network" "data_plane" {
  count = var.data_plane_network_count

  project = var.project_id
  name    = "${var.network_name}-dp-${count.index}"

  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  mtu                     = var.mtu
  description             = "GPUDirect data-plane network ${count.index} for ${var.network_name}"
}

resource "google_compute_subnetwork" "data_plane" {
  count = var.data_plane_network_count

  project = var.project_id
  name    = "${var.network_name}-dp-${count.index}-subnet"
  region  = var.region
  network = google_compute_network.data_plane[count.index].id

  # Carve each data-plane subnet from the configurable base, one /24 per NIC.
  ip_cidr_range = cidrsubnet(var.data_plane_cidr_base, 8, count.index)

  private_ip_google_access = true
}

# ---------------------------------------------------------------------------------------------------------------------
# RDMA network — GPUDirect-RDMA / RoCE (H200 / B200), created with the RoCE network profile
# ---------------------------------------------------------------------------------------------------------------------

resource "google_compute_network" "rdma" {
  count = var.enable_rdma_network ? 1 : 0

  project = var.project_id
  name    = "${var.network_name}-rdma"

  auto_create_subnetworks = false
  mtu                     = var.mtu
  description             = "GPUDirect RDMA/RoCE network for ${var.network_name}"

  # RoCE VPCs are created against a zone-scoped RDMA network profile. routing_mode
  # is not set on profile-backed networks.
  network_profile = var.rdma_network_profile
}

resource "google_compute_subnetwork" "rdma" {
  count = var.enable_rdma_network ? 1 : 0

  project = var.project_id
  name    = "${var.network_name}-rdma-subnet"
  region  = var.region
  network = google_compute_network.rdma[0].id

  ip_cidr_range            = var.rdma_cidr
  private_ip_google_access = true
}
