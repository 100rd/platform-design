# ---------------------------------------------------------------------------------------------------------------------
# Tests for the gke-gpu-scheduling module.
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

run "defaults_to_volcano" {
  command = plan

  assert {
    condition     = length(helm_release.volcano) == 1
    error_message = "Volcano should be the default scheduler for WS-A (ADR-0036)."
  }

  assert {
    condition     = length(helm_release.kueue) == 0
    error_message = "Kueue should not be deployed when scheduler defaults to volcano."
  }
}

run "namespace_carries_adr0028_labels" {
  command = plan

  assert {
    condition     = kubernetes_namespace.scheduling[0].metadata[0].labels["platform.system"] == "ml-infra"
    error_message = "Namespace must carry platform.system = ml-infra per ADR-0028."
  }

  assert {
    condition     = kubernetes_namespace.scheduling[0].metadata[0].labels["platform.component"] == "scheduler"
    error_message = "Scheduling namespace should be labeled platform.component = scheduler."
  }
}

run "volcano_uses_pinned_version" {
  command = plan

  assert {
    condition     = helm_release.volcano[0].version == var.volcano_chart_version
    error_message = "Volcano release must use the pinned volcano_chart_version."
  }
}

run "kueue_selectable" {
  command = plan

  variables {
    scheduler = "kueue"
  }

  assert {
    condition     = length(helm_release.kueue) == 1
    error_message = "Kueue should be deployed when scheduler = kueue."
  }

  assert {
    condition     = length(helm_release.volcano) == 0
    error_message = "Volcano should not be deployed when scheduler = kueue."
  }
}

run "exactly_one_scheduler_deployed" {
  command = plan

  assert {
    condition     = (length(helm_release.kueue) + length(helm_release.volcano)) == 1
    error_message = "Exactly one scheduler must be deployed when enabled."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = (length(helm_release.kueue) + length(helm_release.volcano) + length(kubernetes_namespace.scheduling)) == 0
    error_message = "Nothing should be created when enabled = false."
  }
}
