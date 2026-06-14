variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "subnet_cidr" {
  description = "Primary CIDR for the subnet"
  type        = string
  default     = "10.200.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0042 — GPU high-performance fabric
# ---------------------------------------------------------------------------------------------------------------------

variable "mtu" {
  description = "MTU for the GPU VPC network(s). ADR-0042 D1 sets the jumbo-frame baseline (8896) required for GPUDirect/RoCE; GCP accepts 1300–8896."
  type        = number
  default     = 8896

  validation {
    condition     = var.mtu >= 1300 && var.mtu <= 8896
    error_message = "mtu must be between 1300 and 8896 (GCP VPC MTU range)."
  }
}

variable "data_plane_network_count" {
  description = "Number of GPUDirect-TCPX/TCPXO data-plane networks to create (ADR-0042 D2): 0 = none, 4 = a3-highgpu-8g (TCPX), 8 = a3-megagpu-8g (TCPXO). Each is an independent VPC + /24 subnet attached as an extra GPU NIC."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 4, 8], var.data_plane_network_count)
    error_message = "data_plane_network_count must be 0 (none), 4 (TCPX/a3-high), or 8 (TCPXO/a3-mega)."
  }
}

variable "data_plane_cidr_base" {
  description = "Base CIDR from which each data-plane subnet is carved as a /24 (cidrsubnet(base, 8, index)). Must not overlap the primary subnet_cidr."
  type        = string
  default     = "10.220.0.0/16"
}

variable "enable_rdma_network" {
  description = "Create a dedicated GPUDirect-RDMA / RoCE network (ADR-0042 D3) for H200/B200 (a3-ultragpu-8g, a4-highgpu-8g), consumed by GKE managed DRANET. Requires rdma_network_profile."
  type        = bool
  default     = false
  nullable    = false
}

variable "rdma_network_profile" {
  description = "Zone-scoped RoCE network profile self-link for the RDMA VPC (e.g. projects/PROJECT/global/networkProfiles/ZONE-vpc-roce). Required when enable_rdma_network = true."
  type        = string
  default     = null
}

variable "rdma_cidr" {
  description = "CIDR for the RDMA subnet. Must not overlap the primary or data-plane ranges."
  type        = string
  default     = "10.230.0.0/16"
}
