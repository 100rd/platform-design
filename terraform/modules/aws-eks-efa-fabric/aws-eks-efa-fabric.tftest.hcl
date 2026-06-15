# Tests for aws-eks-efa-fabric. helm + kubernetes mocked; module default-OFF.
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_name = "aws-eks-gpu-test"
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-platform"
  }
}

run "default_off_creates_nothing" {
  command = plan

  assert {
    condition     = length(helm_release.efa_device_plugin) == 0
    error_message = "No EFA device plugin when enabled defaults to false (apply-gated)."
  }

  assert {
    condition     = length(kubernetes_manifest.efa_device_class) == 0
    error_message = "No EFA DeviceClass when disabled."
  }
}

run "device_plugin_mode_under_karpenter" {
  command = plan

  variables {
    enabled     = true
    mode        = "device-plugin"
    provisioner = "karpenter"
  }

  assert {
    condition     = length(helm_release.efa_device_plugin) == 1
    error_message = "device-plugin mode must deploy the DaemonSet (ADR-0045 D2)."
  }

  assert {
    condition     = length(kubernetes_manifest.efa_device_class) == 0
    error_message = "device-plugin mode must NOT create DRA objects."
  }

  assert {
    condition     = output.efa_resource_name == "vpc.amazonaws.com/efa"
    error_message = "device-plugin mode must expose vpc.amazonaws.com/efa."
  }
}

run "dra_mode_on_managed_node_group" {
  command = plan

  variables {
    enabled     = true
    mode        = "dra"
    provisioner = "managed-node-group"
  }

  assert {
    condition     = length(kubernetes_manifest.efa_device_class) == 1
    error_message = "dra mode must create the netdev DeviceClass (ADR-0045 D3)."
  }

  assert {
    condition     = length(kubernetes_manifest.efa_claim_template) == 1
    error_message = "dra mode must create the ResourceClaimTemplate."
  }

  assert {
    condition     = length(helm_release.efa_device_plugin) == 0
    error_message = "dra mode must NOT deploy the device plugin."
  }
}

run "dra_under_karpenter_rejected" {
  command = plan

  variables {
    enabled     = true
    mode        = "dra"
    provisioner = "karpenter"
  }

  expect_failures = [terraform_data.provisioner_guard]
}

run "adr0028_labels" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.platform_labels["platform.system"] == "ml-platform"
    error_message = "platform.system must be ml-platform."
  }

  assert {
    condition     = local.platform_labels["platform.component"] == "gpu-fabric"
    error_message = "platform.component must be gpu-fabric."
  }
}
