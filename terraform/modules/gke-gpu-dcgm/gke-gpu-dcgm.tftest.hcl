# ---------------------------------------------------------------------------------------------------------------------
# Tests for the gke-gpu-dcgm module.
# helm and kubernetes providers are mocked — no cluster or credentials required.
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

run "deploys_exporter_when_enabled" {
  command = plan

  assert {
    condition     = length(helm_release.dcgm_exporter) == 1
    error_message = "DCGM exporter Helm release should be created when enabled = true."
  }

  assert {
    condition     = length(kubernetes_namespace.dcgm) == 1
    error_message = "Namespace should be created when enabled = true."
  }
}

run "namespace_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_namespace.dcgm[0].metadata[0].labels["platform.system"] == "ml-infra"
    error_message = "Namespace must carry platform.system = ml-infra per ADR-0028."
  }

  assert {
    condition     = kubernetes_namespace.dcgm[0].metadata[0].labels["platform.component"] == "observability"
    error_message = "DCGM namespace should be labeled with platform.component = observability."
  }
}

run "release_uses_pinned_version" {
  command = plan

  assert {
    condition     = helm_release.dcgm_exporter[0].version == var.chart_version
    error_message = "Helm release must use the pinned chart_version."
  }
}

run "metrics_port_default_9400" {
  command = plan

  assert {
    condition     = var.exporter_port == 9400
    error_message = "DCGM exporter should default to the standard 9400 metrics port."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(helm_release.dcgm_exporter) == 0
    error_message = "No Helm release should be created when enabled = false."
  }

  assert {
    condition     = length(kubernetes_namespace.dcgm) == 0
    error_message = "No namespace should be created when enabled = false."
  }
}
