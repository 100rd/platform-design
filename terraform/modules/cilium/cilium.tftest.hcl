# NOTE: Cilium module uses yamlencode with conditional expressions that cause
# "Inconsistent conditional result types" with mock_provider plan evaluation.
# Tests are limited to variable-default validation which does not evaluate resources.
#
# NOTE: aws provider is mocked so no real AWS credentials are needed.
# The IRSA resources (aws_iam_role, aws_iam_policy) are exercised via mock provider.

mock_provider "aws" {}
mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_name              = "test-eu-central-1-minimal-platform"
  cluster_endpoint          = "ABCDEF1234567890.gr7.us-east-1.eks.amazonaws.com"
  cluster_oidc_issuer_url   = "https://oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890"
  cluster_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/ABCDEF1234567890ABCDEF1234567890"
}

run "default_cilium_version" {
  command = plan

  assert {
    condition     = var.cilium_version == "1.17.1"
    error_message = "Default Cilium version should be 1.17.1"
  }
}

run "hubble_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_hubble == true
    error_message = "Hubble should be enabled by default"
  }
}

run "hubble_ui_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_hubble_ui == true
    error_message = "Hubble UI should be enabled by default"
  }
}

run "kube_proxy_not_replaced_by_default" {
  command = plan

  assert {
    condition     = var.replace_kube_proxy == false
    error_message = "Kube-proxy should not be replaced by default for safer migration"
  }
}

run "irsa_role_name_uses_cluster_name" {
  command = plan

  assert {
    condition     = aws_iam_role.cilium_operator.name == "test-eu-central-1-minimal-platform-cilium-operator"
    error_message = "IAM role name should be <cluster_name>-cilium-operator"
  }
}
