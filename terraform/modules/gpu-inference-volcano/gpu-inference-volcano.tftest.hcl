mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {}

run "default_chart_version" {
  command = plan

  assert {
    condition     = length(var.chart_version) > 0
    error_message = "Chart version should have a default value"
  }
}

run "module_initializes" {
  command = plan

  assert {
    condition     = true
    error_message = "Module should initialize without errors"
  }
}
