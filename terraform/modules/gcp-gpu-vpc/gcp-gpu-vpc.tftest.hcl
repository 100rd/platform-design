mock_provider "google" {}

variables {
  project_id   = "test-gcp-project"
  network_name = "gpu-test"
  region       = "us-central1"
  environment  = "test"
  labels = {
    "platform.system" = "ml-infra"
  }
}

run "module_initializes" {
  command = plan

  assert {
    condition     = var.project_id == "test-gcp-project"
    error_message = "Module should initialize without errors"
  }
}

run "jumbo_frames_default" {
  command = plan

  # ADR-0042 D1: the GPU VPC must default to the 8896 jumbo-frame baseline.
  assert {
    condition     = google_compute_network.this.mtu == 8896
    error_message = "Primary GPU VPC must default to MTU 8896 (ADR-0042 D1)."
  }
}

run "no_fabric_networks_by_default" {
  command = plan

  assert {
    condition     = length(google_compute_network.data_plane) == 0
    error_message = "No data-plane networks should be created by default."
  }

  assert {
    condition     = length(google_compute_network.rdma) == 0
    error_message = "No RDMA network should be created by default."
  }
}

run "tcpx_creates_four_data_plane_networks" {
  command = plan

  variables {
    data_plane_network_count = 4
  }

  assert {
    condition     = length(google_compute_network.data_plane) == 4
    error_message = "TCPX (a3-high) must create 4 data-plane networks."
  }

  assert {
    condition     = google_compute_network.data_plane[0].mtu == 8896
    error_message = "Data-plane networks must inherit the jumbo MTU."
  }
}

run "roce_creates_rdma_network" {
  command = plan

  variables {
    enable_rdma_network  = true
    rdma_network_profile = "projects/test-gcp-project/global/networkProfiles/us-central1-a-vpc-roce"
  }

  assert {
    condition     = length(google_compute_network.rdma) == 1
    error_message = "Enabling RDMA must create exactly one RoCE network."
  }
}
