# GKE CRDs (GKENetworkParamSet/Network) + DaemonSet via kubernetes_manifest; provider
# mocked so plan/validate needs no live cluster.
mock_provider "kubernetes" {}

variables {
  mode = "tcpx"
  data_plane_networks = [
    { name = "gpu-dp-0", network = "gpu-dp-0", subnetwork = "gpu-dp-0-subnet" },
    { name = "gpu-dp-1", network = "gpu-dp-1", subnetwork = "gpu-dp-1-subnet" },
    { name = "gpu-dp-2", network = "gpu-dp-2", subnetwork = "gpu-dp-2-subnet" },
    { name = "gpu-dp-3", network = "gpu-dp-3", subnetwork = "gpu-dp-3-subnet" },
  ]
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-infra"
  }
}

run "tcpx_wires_four_param_sets_and_networks" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.param_set) == 4
    error_message = "TCPX must create 4 GKENetworkParamSet objects (one per data-plane VPC)."
  }

  assert {
    condition     = length(kubernetes_manifest.network) == 4
    error_message = "TCPX must create 4 Device-type Network objects."
  }
}

run "param_set_uses_netdevice_mode" {
  command = plan

  assert {
    condition     = kubernetes_manifest.param_set["gpu-dp-0"].manifest.spec.deviceMode == "NetDevice"
    error_message = "GKENetworkParamSet must use deviceMode = NetDevice for GPUDirect."
  }
}

run "installer_selects_fabric_mode_nodes" {
  command = plan

  assert {
    condition     = kubernetes_manifest.nccl_installer[0].manifest.spec.template.spec.nodeSelector["fabric-mode"] == "tcpx"
    error_message = "NCCL installer DaemonSet must node-select fabric-mode = tcpx."
  }
}

run "installer_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_manifest.nccl_installer[0].manifest.metadata.labels["platform.system"] == "ml-infra"
    error_message = "NCCL installer must carry platform.system = ml-infra (ADR-0028)."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = (length(kubernetes_manifest.param_set) + length(kubernetes_manifest.network) + length(kubernetes_manifest.nccl_installer)) == 0
    error_message = "Nothing should be created when enabled = false."
  }
}
