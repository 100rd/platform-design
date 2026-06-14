mock_provider "google" {}

variables {
  project_id   = "test-gcp-project"
  cluster_id   = "projects/test-gcp-project/locations/us-central1-a/clusters/test"
  cluster_name = "test-gke-cluster"
  zone         = "us-central1-a"

  node_pool_configs = {}
}

run "module_initializes" {
  command = plan

  # A real reference (the parser rejects a bare `true`). The module plans cleanly
  # with an empty node-pool map and the new switch at its default.
  assert {
    condition     = var.operator_managed_driver == false
    error_message = "Module should initialize with operator_managed_driver defaulting to false."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# operator_managed_driver — additive switch. Default false must preserve current
# behavior; true hands the driver stack to the NVIDIA GPU Operator (ADR-0036).
# ---------------------------------------------------------------------------------------------------------------------

run "default_false_keeps_gke_managed_driver" {
  command = plan

  variables {
    node_pool_configs = {
      l4 = {
        machine_type      = "g2-standard-8"
        accelerator_type  = "nvidia-l4"
        accelerator_count = 1
        min_node_count    = 0
        max_node_count    = 3
      }
    }
  }

  # Default must be false (zero-diff path).
  assert {
    condition     = var.operator_managed_driver == false
    error_message = "operator_managed_driver must default to false."
  }

  # GKE-managed driver block present at LATEST when operator_managed_driver = false.
  assert {
    condition     = google_container_node_pool.this["l4"].node_config[0].guest_accelerator[0].gpu_driver_installation_config[0].gpu_driver_version == "LATEST"
    error_message = "Default path must keep the GKE-managed gpu_driver_installation_config at LATEST."
  }

  # No operator-driver labels are injected on the default path (zero diff).
  assert {
    condition     = !contains(keys(google_container_node_pool.this["l4"].node_config[0].labels), "gke-no-default-nvidia-gpu-device-plugin")
    error_message = "Default path must NOT add the gke-no-default-nvidia-gpu-device-plugin label."
  }

  assert {
    condition     = !contains(keys(google_container_node_pool.this["l4"].node_config[0].labels), "nvidia.com/gpu.present")
    error_message = "Default path must NOT add the nvidia.com/gpu.present label."
  }

  # Baseline labels remain exactly as before.
  assert {
    condition     = google_container_node_pool.this["l4"].node_config[0].labels["managed-by"] == "terraform"
    error_message = "Default path must keep the managed-by = terraform label."
  }
}

run "operator_managed_driver_true_omits_driver_and_adds_labels" {
  command = plan

  variables {
    operator_managed_driver = true

    node_pool_configs = {
      l4 = {
        machine_type      = "g2-standard-8"
        accelerator_type  = "nvidia-l4"
        accelerator_count = 1
        min_node_count    = 0
        max_node_count    = 3
      }
    }
  }

  # GKE-managed driver block is omitted when the operator owns the driver.
  assert {
    condition     = length(google_container_node_pool.this["l4"].node_config[0].guest_accelerator[0].gpu_driver_installation_config) == 0
    error_message = "operator_managed_driver = true must omit the gpu_driver_installation_config block."
  }

  # Operator-driver labels are injected.
  assert {
    condition     = google_container_node_pool.this["l4"].node_config[0].labels["gke-no-default-nvidia-gpu-device-plugin"] == "true"
    error_message = "operator_managed_driver = true must add gke-no-default-nvidia-gpu-device-plugin = true."
  }

  assert {
    condition     = google_container_node_pool.this["l4"].node_config[0].labels["nvidia.com/gpu.present"] == "true"
    error_message = "operator_managed_driver = true must add nvidia.com/gpu.present = true."
  }

  # Baseline labels are still present alongside the operator labels.
  assert {
    condition     = google_container_node_pool.this["l4"].node_config[0].labels["managed-by"] == "terraform"
    error_message = "Operator path must still carry the baseline managed-by = terraform label."
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ADR-0042 — GPU fabric: gVNIC baseline (D1) + per-family fabric attach (D2/D3).
# ---------------------------------------------------------------------------------------------------------------------

run "gvnic_on_and_no_extra_nics_by_default" {
  command = plan

  variables {
    node_pool_configs = {
      a100 = {
        machine_type      = "a2-ultragpu-1g"
        accelerator_type  = "nvidia-a100-80gb"
        accelerator_count = 1
      }
    }
  }

  # D1: gVNIC defaults on.
  assert {
    condition     = google_container_node_pool.this["a100"].node_config[0].gvnic[0].enabled == true
    error_message = "gVNIC must default to enabled (ADR-0042 D1)."
  }

  # fabric_mode defaults to "none" → recorded as a node label.
  assert {
    condition     = google_container_node_pool.this["a100"].node_config[0].labels["fabric-mode"] == "none"
    error_message = "fabric-mode label must default to none."
  }

  # No additional NICs unless requested → no network_config block.
  assert {
    condition     = length(google_container_node_pool.this["a100"].network_config) == 0
    error_message = "No network_config (extra NICs) should be created by default."
  }
}

run "tcpx_attaches_four_data_plane_nics" {
  command = plan

  variables {
    node_pool_configs = {
      h100 = {
        machine_type      = "a3-highgpu-8g"
        accelerator_type  = "nvidia-h100-80gb"
        accelerator_count = 8
        fabric_mode       = "tcpx"
        additional_node_networks = [
          { network = "gpu-dp-0", subnetwork = "gpu-dp-0-subnet" },
          { network = "gpu-dp-1", subnetwork = "gpu-dp-1-subnet" },
          { network = "gpu-dp-2", subnetwork = "gpu-dp-2-subnet" },
          { network = "gpu-dp-3", subnetwork = "gpu-dp-3-subnet" },
        ]
      }
    }
  }

  assert {
    condition     = google_container_node_pool.this["h100"].node_config[0].labels["fabric-mode"] == "tcpx"
    error_message = "H100 pool must carry fabric-mode = tcpx."
  }

  assert {
    condition     = length(google_container_node_pool.this["h100"].network_config[0].additional_node_network_configs) == 4
    error_message = "TCPX H100 pool must attach 4 data-plane NICs."
  }
}

