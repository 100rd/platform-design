mock_provider "kubernetes" {}

variables {
  cluster_name = "test-cluster"
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == false
    error_message = "HPA defaults should be disabled by default"
  }
}
