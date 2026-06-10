# ---------------------------------------------------------------------------------------------------------------------
# Tests for the gke-gpu-operator module.
# helm and kubernetes providers are mocked so no real cluster or credentials are
# needed; assertions run at plan time over the module's wiring and toggles.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  platform_labels = {
    "platform.env"   = "staging"
    "platform.owner" = "team-data"
  }
}

run "default_chart_version_pinned" {
  command = plan

  assert {
    condition     = length(var.chart_version) > 0
    error_message = "Chart version must have a pinned default."
  }
}

run "deploys_operator_when_enabled" {
  command = plan

  assert {
    condition     = length(helm_release.gpu_operator) == 1
    error_message = "GPU operator Helm release should be created when enabled = true."
  }

  assert {
    condition     = length(kubernetes_namespace.gpu_operator) == 1
    error_message = "Namespace should be created when enabled = true."
  }
}

run "namespace_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.system"] == "ml-infra"
    error_message = "Namespace must carry platform.system = ml-infra per ADR-0028."
  }

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.env"] == "staging"
    error_message = "Caller-supplied platform.env label must be merged onto the namespace."
  }
}

run "release_uses_pinned_version" {
  command = plan

  assert {
    condition     = helm_release.gpu_operator[0].version == var.chart_version
    error_message = "Helm release must use the pinned chart_version."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(helm_release.gpu_operator) == 0
    error_message = "No Helm release should be created when enabled = false."
  }

  assert {
    condition     = length(kubernetes_namespace.gpu_operator) == 0
    error_message = "No namespace should be created when enabled = false."
  }
}
