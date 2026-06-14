# ---------------------------------------------------------------------------------------------------------------------
# GCP GKE GPU Node Pools Module
# ---------------------------------------------------------------------------------------------------------------------
# Creates GPU-capable GKE node pools using google_container_node_pool with for_each
# over a configurable map. Supports NVIDIA GPU accelerators with automatic driver
# installation, spot instances, custom taints/labels, and Workload Identity.
#
# Each node pool is pinned to a single zone for GPU locality and uses autoscaling
# to optimize cost while meeting capacity requirements.
#
# When var.operator_managed_driver = true the module hands GPU driver/device-plugin
# ownership to the NVIDIA GPU Operator (ADR-0036): the gpu_driver_installation_config
# block is omitted (no GKE-managed driver) and the nodes are labeled to disable the
# default GKE NVIDIA device plugin. Default false preserves the GKE-managed driver
# (gpu_driver_version = "LATEST") byte-for-byte.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Extra node labels applied ONLY when the NVIDIA GPU Operator owns the driver stack.
  # Empty map when operator_managed_driver = false → zero diff vs. the GKE-managed path.
  operator_driver_labels = var.operator_managed_driver ? {
    "gke-no-default-nvidia-gpu-device-plugin" = "true"
    "nvidia.com/gpu.present"                  = "true"
  } : {}
}

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

        # GKE-managed driver. Omitted when the NVIDIA GPU Operator owns the driver
        # (operator_managed_driver = true). Default false keeps the LATEST driver.
        dynamic "gpu_driver_installation_config" {
          for_each = var.operator_managed_driver ? [] : [1]
          content {
            gpu_driver_version = "LATEST"
          }
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

    # Labels — merge per-pool labels with common labels. operator_driver_labels is
    # empty unless operator_managed_driver = true, so the default path is unchanged.
    labels = merge(
      var.labels,
      each.value.labels,
      {
        "managed-by"   = "terraform"
        "cluster-role" = "gpu-analysis"
        "node-pool"    = each.key
        # ADR-0042: record the fabric mode so gke-gpu-fabric / gke-gpu-dranet and
        # workloads can node-select the right GPUDirect/RoCE pool.
        "fabric-mode" = each.value.fabric_mode
      },
      local.operator_driver_labels,
    )

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # ADR-0042 D1: gVNIC is the GPU-network baseline and a hard prerequisite for
    # GPUDirect-TCPX/TCPXO and RDMA NICs. On by default; opt-out per pool.
    gvnic {
      enabled = each.value.enable_gvnic
    }

    # Workload Identity — use GKE metadata server
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # ---------------------------------------------------------------------------
  # ADR-0042 D2/D3 — additional GPU NICs (TCPX/TCPXO data-plane or RoCE RDMA).
  # Empty by default → no network_config block, existing pools unchanged.
  # ---------------------------------------------------------------------------
  dynamic "network_config" {
    for_each = length(each.value.additional_node_networks) > 0 ? [1] : []
    content {
      dynamic "additional_node_network_configs" {
        for_each = each.value.additional_node_networks
        content {
          network    = additional_node_network_configs.value.network
          subnetwork = additional_node_network_configs.value.subnetwork
        }
      }
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
