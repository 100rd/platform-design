# Tests for aws-eks-gpu-dcgm. helm + kubernetes providers mocked; module default-OFF.
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
    condition     = length(helm_release.dcgm_exporter) == 0
    error_message = "No DCGM exporter when enabled defaults to false (apply-gated)."
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.taint) == 0
    error_message = "No auto-taint CronJob when disabled."
  }
}

run "deploys_exporter_and_taint_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(helm_release.dcgm_exporter) == 1
    error_message = "DCGM exporter must deploy when enabled."
  }

  assert {
    condition     = helm_release.dcgm_exporter[0].version == var.chart_version
    error_message = "Exporter must use the pinned chart_version."
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.taint) == 1
    error_message = "Auto-taint CronJob must deploy when enabled (ADR-0044 D1)."
  }
}

run "auto_taint_can_be_disabled" {
  command = plan

  variables {
    enabled           = true
    enable_auto_taint = false
  }

  assert {
    condition     = length(kubernetes_cron_job_v1.taint) == 0
    error_message = "Auto-taint CronJob must not deploy when enable_auto_taint = false."
  }

  assert {
    condition     = length(helm_release.dcgm_exporter) == 1
    error_message = "Exporter still deploys even when auto-taint is off."
  }
}

run "namespace_adr0028_labels" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_namespace.dcgm[0].metadata[0].labels["platform.system"] == "ml-platform"
    error_message = "Namespace must carry platform.system = ml-platform."
  }

  assert {
    condition     = kubernetes_namespace.dcgm[0].metadata[0].labels["platform.component"] == "gpu-dcgm"
    error_message = "platform.component must be gpu-dcgm."
  }
}
