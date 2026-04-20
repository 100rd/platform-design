mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_endpoint = "ABCDEF1234567890.gr7.us-east-1.eks.amazonaws.com"
}

run "module_initializes" {
  command = plan

  assert {
    condition     = true
    error_message = "Module should initialize without errors"
  }
}
