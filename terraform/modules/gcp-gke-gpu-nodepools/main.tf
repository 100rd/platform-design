# ---------------------------------------------------------------------------------------------------------------------
# GCP GKE GPU Node Pools Module
# ---------------------------------------------------------------------------------------------------------------------
# Creates GPU-capable GKE node pools using google_container_node_pool with for_each
# over a configurable map. Supports NVIDIA GPU accelerators with automatic driver
# installation, spot instances, custom taints/labels, and Workload Identity.
#
# Each node pool is pinned to a single zone for GPU locality and uses autoscaling
# to optimize cost while meeting capacity requirements.
# ---------------------------------------------------------------------------------------------------------------------

resource "google_container_node_pool" "this" {
  for_each = var.node_pool_configs

  project  = var.project_id
  name     = each.key
  cluster  = var.cluster_id
  location = var.zone

  # ---------------------------------------------------------------------------
  # Autoscaling
  # ---------------------------------------------------------------------------
  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  initial_node_count = each.value.initial_node_count

  # ---------------------------------------------------------------------------
  # Node configuration
  # ---------------------------------------------------------------------------
  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot

    # GPU accelerator — conditional on accelerator_type being set
    dynamic "guest_accelerator" {
      for_each = each.value.accelerator_type != null ? [1] : []
      content {
        type  = each.value.accelerator_type
        count = each.value.accelerator_count

        gpu_driver_installation_config {
          gpu_driver_version = "LATEST"
        }
      }
    }

    # Taints from configuration
    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # Labels — merge per-pool labels with common labels
    labels = merge(
      var.labels,
      each.value.labels,
      {
        "managed-by"   = "terraform"
        "cluster-role" = "gpu-analysis"
        "node-pool"    = each.key
      }
    )

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity — use GKE metadata server
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # ---------------------------------------------------------------------------
  # Management
  # ---------------------------------------------------------------------------
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
