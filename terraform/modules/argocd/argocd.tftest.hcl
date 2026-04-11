mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {}

run "default_chart_version" {
  command = plan

  assert {
    condition     = var.chart_version == "7.8.13"
    error_message = "Default ArgoCD chart version should be 7.8.13"
  }
}

run "default_namespace" {
  command = plan

  assert {
    condition     = var.namespace == "argocd"
    error_message = "Default namespace should be argocd"
  }
}

run "namespace_created_by_default" {
  command = plan

  assert {
    condition     = var.create_namespace == true
    error_message = "Namespace should be created by default"
  }
}

run "ha_disabled_by_default" {
  command = plan

  assert {
    condition     = var.ha_enabled == false
    error_message = "HA mode should be disabled by default"
  }
}

run "dex_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_dex == false
    error_message = "Dex should be disabled by default"
  }
}
