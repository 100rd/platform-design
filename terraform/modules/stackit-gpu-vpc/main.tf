# ---------------------------------------------------------------------------------------------------------------------
# STACKIT GPU Network Module
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an isolated, routed STACKIT virtual network (VPC) in region `eu01` for
# STACKIT Kubernetes Engine (SKE) worker nodes and GPU inference workloads.
# ---------------------------------------------------------------------------------------------------------------------

resource "stackit_network" "this" {
  project_id         = var.project_id
  name               = var.network_name
  region             = var.region
  routed             = var.routed
  ipv4_prefix_length = var.ipv4_prefix_length
  ipv4_nameservers   = var.ipv4_nameservers
  labels             = var.labels
}
