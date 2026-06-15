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

# ---------------------------------------------------------------------------------------------------------------------
# Auto-taint CronJob container hardening (CIS K8s 5.2.x / Pod Security "restricted")
# Path: spec -> job_template -> spec -> template -> spec -> container[0]
# ---------------------------------------------------------------------------------------------------------------------

run "auto_taint_container_security_context" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].security_context[0].run_as_non_root == true
    error_message = "Auto-taint container must set run_as_non_root = true."
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem == true
    error_message = "Auto-taint container must set read_only_root_filesystem = true."
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "Auto-taint container must set allow_privilege_escalation = false."
  }

  assert {
    condition     = contains(kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].security_context[0].capabilities[0].drop, "ALL")
    error_message = "Auto-taint container must drop ALL Linux capabilities."
  }
}

run "auto_taint_container_resources_bounded" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].resources[0].requests["cpu"] == "50m"
    error_message = "Auto-taint container must declare a CPU request (default 50m)."
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].resources[0].requests["memory"] == "64Mi"
    error_message = "Auto-taint container must declare a memory request (default 64Mi)."
  }

  assert {
    condition     = kubernetes_cron_job_v1.taint[0].spec[0].job_template[0].spec[0].template[0].spec[0].container[0].resources[0].limits["memory"] == "128Mi"
    error_message = "Auto-taint container must declare a memory limit (default 128Mi) so a wedged probe cannot starve the node."
  }
}
