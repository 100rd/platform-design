mock_provider "helm" {}

variables {
  cluster_name = "test-cluster"
}

run "disabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == false
    error_message = "WPA should be disabled by default"
  }
}

run "default_wpa_version" {
  command = plan

  assert {
    condition     = var.wpa_version == "0.7.1"
    error_message = "Default WPA version should be 0.7.1"
  }
}

run "default_namespace" {
  command = plan

  assert {
    condition     = var.namespace == "kube-system"
    error_message = "Default namespace should be kube-system"
  }
}

run "single_replica_by_default" {
  command = plan

  assert {
    condition     = var.controller_replicas == 1
    error_message = "Default controller replicas should be 1"
  }
}
