# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-gpu-fabric module. helm + kubernetes providers are mocked;
# assertions run at plan time over the day-0 SR-IOV primary and the gated DRANET target.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  enabled = true
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-data"
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(helm_release.sriov_operator) == 0
    error_message = "No SR-IOV operator when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.sriov_node_policy) == 0
    error_message = "No SR-IOV node policy when enabled = false."
  }
}

run "sriov_is_the_day0_primary" {
  command = plan

  # ADR-0053: SR-IOV/RDMA is the day-0 primary and ships by default.
  assert {
    condition     = length(helm_release.sriov_operator) == 1
    error_message = "SR-IOV operator must deploy as the day-0 primary (ADR-0053)."
  }

  assert {
    condition     = kubernetes_manifest.sriov_node_policy[0].manifest.spec.isRdma == true
    error_message = "SR-IOV node policy must enable RDMA (GPUDirect)."
  }

  assert {
    condition     = kubernetes_manifest.sriov_node_policy[0].manifest.spec.mtu == 9000
    error_message = "Fabric MTU must be 9000 (jumbo frames, ADR-0053)."
  }
}

run "infiniband_link_type" {
  command = plan

  # Default fabric_mode = infiniband → link type ib.
  assert {
    condition     = kubernetes_manifest.sriov_node_policy[0].manifest.spec.linkType == "ib"
    error_message = "InfiniBand mode must set linkType = ib."
  }
}

run "roce_link_type" {
  command = plan

  variables {
    fabric_mode = "roce"
  }

  assert {
    condition     = kubernetes_manifest.sriov_node_policy[0].manifest.spec.linkType == "eth"
    error_message = "RoCEv2 mode must set linkType = eth (Ethernet)."
  }
}

run "dranet_is_gated_off_by_default" {
  command = plan

  # ADR-0053 D3 maturity gate: DRANET is OFF until validated.
  assert {
    condition     = length(kubernetes_manifest.dranet_device_class) == 0
    error_message = "DRANET (Cilium netdev DRA) must be OFF by default (ADR-0053 D3 gate)."
  }

  assert {
    condition     = output.dranet_enabled == false
    error_message = "dranet_enabled must be false by default."
  }
}

run "dranet_objects_when_enabled" {
  command = plan

  variables {
    enable_dranet = true
  }

  assert {
    condition     = length(kubernetes_manifest.dranet_device_class) == 1 && length(kubernetes_manifest.dranet_claim_template) == 1
    error_message = "DRANET DeviceClass + ResourceClaimTemplate must be created when enable_dranet = true."
  }
}
