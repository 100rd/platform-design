# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-gpu-operator module. helm + kubernetes providers are mocked;
# assertions run at plan time over the driver-less wiring (ADR-0050).
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
    condition     = length(helm_release.gpu_operator) == 0
    error_message = "No operator release when enabled = false."
  }

  assert {
    condition     = length(kubernetes_namespace.gpu_operator) == 0
    error_message = "No namespace when enabled = false."
  }
}

run "deploys_operator_when_enabled" {
  command = plan

  assert {
    condition     = helm_release.gpu_operator[0].version == var.chart_version
    error_message = "Operator must use the pinned chart version."
  }

  assert {
    condition     = kubernetes_namespace.gpu_operator[0].metadata[0].labels["platform.system"] == "ml-infra"
    error_message = "Namespace must carry platform.system = ml-infra (ADR-0028)."
  }
}

run "operator_runs_driver_less" {
  command = plan

  # ADR-0050: the driver + toolkit ship in the Talos system extension, NEVER the Operator.
  assert {
    condition     = output.driver_less == true
    error_message = "Operator must run driver-less on bare-metal Talos (ADR-0050)."
  }
}

run "driver_install_is_rejected" {
  command = plan

  variables {
    driver_enabled = true
  }

  # The validation block must fail the plan — the Operator cannot install a driver on Talos.
  expect_failures = [var.driver_enabled]
}
