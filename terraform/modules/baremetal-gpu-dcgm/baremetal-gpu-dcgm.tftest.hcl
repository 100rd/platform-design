# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-gpu-dcgm module. helm + kubernetes providers are mocked;
# assertions run at plan time over the exporter + auto-taint wiring.
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
    condition     = length(helm_release.dcgm_exporter) == 0
    error_message = "No DCGM exporter when enabled = false."
  }

  assert {
    condition     = length(kubernetes_manifest.gpu_health_autotaint) == 0
    error_message = "No auto-taint CronJob when enabled = false."
  }
}

run "deploys_exporter_with_servicemonitor" {
  command = plan

  assert {
    condition     = helm_release.dcgm_exporter[0].version == var.chart_version
    error_message = "DCGM exporter must use the pinned chart version."
  }

  assert {
    condition     = kubernetes_namespace.dcgm[0].metadata[0].labels["platform.system"] == "ml-infra"
    error_message = "DCGM namespace must carry platform.system = ml-infra (ADR-0028)."
  }
}

run "auto_taint_cronjob_present_by_default" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.gpu_health_autotaint) == 1
    error_message = "GPU-health auto-taint CronJob must be created by default (XID-burst node taint)."
  }

  assert {
    condition     = output.auto_taint_enabled == true
    error_message = "auto_taint_enabled must be true by default."
  }
}

run "auto_taint_can_be_disabled" {
  command = plan

  variables {
    enable_auto_taint = false
  }

  assert {
    condition     = length(kubernetes_manifest.gpu_health_autotaint) == 0
    error_message = "Auto-taint CronJob must not be created when enable_auto_taint = false."
  }
}
