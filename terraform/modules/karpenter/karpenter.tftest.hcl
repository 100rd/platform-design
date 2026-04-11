mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "aws" {}

variables {
  cluster_name                      = "test-cluster"
  cluster_endpoint                  = "https://ABCDEF1234.gr7.us-east-1.eks.amazonaws.com"
  karpenter_controller_role_arn     = "arn:aws:iam::123456789012:role/karpenter-controller"
  karpenter_interruption_queue_name = "test-cluster-karpenter"
  karpenter_node_iam_role_name      = "test-cluster-karpenter-node"
}

run "default_karpenter_version" {
  command = plan

  assert {
    condition     = var.karpenter_version == "1.10.0"
    error_message = "Default Karpenter version should be 1.10.0"
  }
}

run "helm_release_created" {
  command = plan

  assert {
    condition     = helm_release.karpenter.name == "karpenter"
    error_message = "Karpenter Helm release name should be 'karpenter'"
  }
}

run "deployed_to_kube_system" {
  command = plan

  assert {
    condition     = helm_release.karpenter.namespace == "kube-system"
    error_message = "Karpenter should be deployed to kube-system namespace"
  }
}
