# Tests for aws-eks-gpu-operator. helm + kubernetes providers mocked; module default-OFF.
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-ml-platform"
  }
}

run "default_off_creates_nothing" {
  command = plan

  assert {
    condition     = length(helm_release.gpu_operator) == 0
    error_message = "No Helm release when enabled defaults to false (apply-gated)."
  }
}

run "deploys_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(helm_release.gpu_operator) == 1
    error_message = "GPU operator must deploy when enabled = true."
  }

  assert {
    condition     = helm_release.gpu_operator[0].version == var.chart_version
    error_message = "Helm release must use the pinned chart_version."
  }
}

run "bottlerocket_driver_off" {
  command = plan

  variables {
    enabled = true
    node_os = "bottlerocket"
  }

  assert {
    condition     = local.driver_enabled == false
    error_message = "On Bottlerocket the driver is pre-baked — driver_enabled must be false (ADR-0044 D1)."
  }
}

run "al2023_driver_on" {
  command = plan

  variables {
    enabled = true
    node_os = "al2023"
  }

  assert {
    condition     = local.driver_enabled == true
    error_message = "On AL2023 the operator installs the driver — driver_enabled must be true (ADR-0044 D1)."
  }
}

run "namespace_adr0028_labels" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.system"] == "ml-platform"
    error_message = "Namespace must carry platform.system = ml-platform (ADR-0028/0044 D6)."
  }

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.component"] == "gpu-operator"
    error_message = "platform.component must be gpu-operator."
  }

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.owner"] == "team-ml-platform"
    error_message = "Caller-supplied platform.owner must be merged."
  }
}
