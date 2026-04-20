mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {}

run "default_chart_version" {
  command = plan

  assert {
    condition     = var.chart_version == "4.16.1"
    error_message = "Default Falco chart version should be 4.16.1"
  }
}

run "default_namespace" {
  command = plan

  assert {
    condition     = var.namespace == "falco-system"
    error_message = "Default namespace should be falco-system"
  }
}

run "namespace_created_by_default" {
  command = plan

  assert {
    condition     = var.create_namespace == true
    error_message = "Namespace should be created by default"
  }
}

run "sidekick_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_sidekick == true
    error_message = "Falcosidekick should be enabled by default"
  }
}

run "modern_ebpf_driver_by_default" {
  command = plan

  assert {
    condition     = var.driver_kind == "modern_ebpf"
    error_message = "Default driver should be modern_ebpf"
  }
}
