mock_provider "kubernetes" {}

variables {}

run "default_hugepage_size" {
  command = plan

  assert {
    condition     = var.hugepage_size == "1Gi"
    error_message = "Default hugepage size should be 1Gi"
  }
}

run "module_initializes" {
  command = plan

  assert {
    condition     = true
    error_message = "Module should initialize without errors"
  }
}
