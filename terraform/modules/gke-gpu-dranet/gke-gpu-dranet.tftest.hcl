# DRA objects are kubernetes_manifest; the kubernetes provider is mocked so plan/validate
# needs no live cluster (matches the gpu-inference-dra pattern).
mock_provider "kubernetes" {}

variables {
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-infra"
  }
}

run "creates_deviceclass_and_claim_template" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.deviceclass_roce) == 1
    error_message = "A RoCE netdev DeviceClass must be created when enabled."
  }

  assert {
    condition     = length(kubernetes_manifest.claimtemplate_rdma) == 1
    error_message = "An RDMA ResourceClaimTemplate must be created when enabled."
  }
}

run "objects_carry_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_manifest.deviceclass_roce[0].manifest.metadata.labels["platform.system"] == "ml-infra"
    error_message = "DeviceClass must carry platform.system = ml-infra (ADR-0028)."
  }

  assert {
    condition     = kubernetes_manifest.deviceclass_roce[0].manifest.metadata.labels["platform.component"] == "gpu-fabric"
    error_message = "DeviceClass must carry platform.component = gpu-fabric."
  }
}

run "claim_requests_all_rdma_nics" {
  command = plan

  assert {
    condition     = kubernetes_manifest.claimtemplate_rdma[0].manifest.spec.spec.devices.requests[0].allocationMode == "All"
    error_message = "RDMA claim must request All NICs (3.2 Tbps across the CX-7 fabric)."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = (length(kubernetes_manifest.deviceclass_roce) + length(kubernetes_manifest.claimtemplate_rdma)) == 0
    error_message = "Nothing should be created when enabled = false."
  }
}
