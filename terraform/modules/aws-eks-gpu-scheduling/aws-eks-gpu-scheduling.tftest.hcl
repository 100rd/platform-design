# Tests for aws-eks-gpu-scheduling. helm + kubernetes providers mocked; module default-OFF.
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
    condition     = length(helm_release.volcano) == 0
    error_message = "No Volcano release when enabled defaults to false (apply-gated)."
  }

  assert {
    condition     = length(kubernetes_manifest.device_class) == 0
    error_message = "No DRA DeviceClasses when disabled."
  }
}

run "deploys_volcano_and_dra_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(helm_release.volcano) == 1
    error_message = "Volcano must deploy when enabled."
  }

  assert {
    condition     = helm_release.volcano[0].version == var.chart_version
    error_message = "Volcano must use the pinned chart_version."
  }

  assert {
    condition     = length(kubernetes_manifest.device_class) == 3
    error_message = "Default DRA DeviceClasses (h100/a100/b200) must be created (ADR-0044 D2)."
  }

  assert {
    condition     = length(kubernetes_manifest.resource_claim_template) == 2
    error_message = "Default ResourceClaimTemplates must be created."
  }
}

run "namespace_adr0028_labels" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = kubernetes_namespace.scheduling[0].metadata[0].labels["platform.system"] == "ml-platform"
    error_message = "Namespace must carry platform.system = ml-platform."
  }

  assert {
    condition     = kubernetes_namespace.scheduling[0].metadata[0].labels["platform.component"] == "gpu-scheduling"
    error_message = "platform.component must be gpu-scheduling."
  }
}

run "dra_objects_can_be_empty" {
  command = plan

  variables {
    enabled                  = true
    device_classes           = {}
    resource_claim_templates = {}
  }

  assert {
    condition     = length(kubernetes_manifest.device_class) == 0
    error_message = "No DeviceClasses when device_classes is empty."
  }

  assert {
    condition     = length(helm_release.volcano) == 1
    error_message = "Volcano still deploys with empty DRA maps."
  }
}
