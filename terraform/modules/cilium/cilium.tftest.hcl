# NOTE: Cilium module uses yamlencode with conditional expressions that cause
# "Inconsistent conditional result types" with mock_provider plan evaluation.
# Tests are limited to variable-default validation which does not evaluate resources.

mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_endpoint = "ABCDEF1234567890.gr7.us-east-1.eks.amazonaws.com"
}

run "default_cilium_version" {
  command = plan

  assert {
    condition     = var.cilium_version == "1.17.1"
    error_message = "Default Cilium version should be 1.17.1"
  }
}

run "hubble_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_hubble == true
    error_message = "Hubble should be enabled by default"
  }
}

run "hubble_ui_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_hubble_ui == true
    error_message = "Hubble UI should be enabled by default"
  }
}

run "kube_proxy_not_replaced_by_default" {
  command = plan

  assert {
    condition     = var.replace_kube_proxy == false
    error_message = "Kube-proxy should not be replaced by default for safer migration"
  }
}
