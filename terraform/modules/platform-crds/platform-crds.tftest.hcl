mock_provider "kubectl" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "http" {}

variables {}

run "default_argocd_version" {
  command = plan

  assert {
    condition     = var.argocd_version == "2.14.2"
    error_message = "Default ArgoCD version should be 2.14.2"
  }
}

run "default_cert_manager_version" {
  command = plan

  assert {
    condition     = var.cert_manager_version == "1.17.2"
    error_message = "Default cert-manager version should be 1.17.2"
  }
}

run "default_external_secrets_version" {
  command = plan

  assert {
    condition     = var.external_secrets_version == "0.14.1"
    error_message = "Default External Secrets version should be 0.14.1"
  }
}
