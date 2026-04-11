mock_provider "kubernetes" {}

variables {}

run "default_model_name" {
  command = plan

  assert {
    condition     = length(var.model_name) > 0
    error_message = "Model name should have a default value"
  }
}

run "single_replica_by_default" {
  command = plan

  assert {
    condition     = var.replicas == 1
    error_message = "Default replicas should be 1"
  }
}
