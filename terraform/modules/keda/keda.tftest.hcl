mock_provider "helm" {}
mock_provider "kubernetes" {}

variables {
  cluster_name = "test-cluster"
}

run "default_keda_version" {
  command = plan

  assert {
    condition     = var.keda_version == "2.16.1"
    error_message = "Default KEDA version should be 2.16.1"
  }
}

run "default_namespace" {
  command = plan

  assert {
    condition     = var.namespace == "kube-system"
    error_message = "Default namespace should be kube-system"
  }
}

run "single_operator_replica_by_default" {
  command = plan

  assert {
    condition     = var.operator_replicas == 1
    error_message = "Default operator replicas should be 1"
  }
}
