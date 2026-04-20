mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_name = "test-gpu-cluster"
}

run "module_initializes" {
  command = plan

  assert {
    condition     = true
    error_message = "Module should initialize without errors"
  }
}
