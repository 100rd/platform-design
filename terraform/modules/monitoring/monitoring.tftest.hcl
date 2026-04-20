mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "aws" {}

variables {
  cluster_name      = "test-cluster"
  oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/ABCDEF"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "prometheus_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_prometheus == true
    error_message = "Prometheus should be enabled by default"
  }
}

run "grafana_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_grafana == true
    error_message = "Grafana should be enabled by default"
  }
}
