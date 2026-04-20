mock_provider "kubernetes" {}

variables {
  cluster_name       = "test-cluster"
  node_iam_role_name = "test-cluster-karpenter-node"
  nodepool_configs = {
    general = {
      enabled           = true
      cpu_limit         = 100
      memory_limit      = 200
      spot_percentage   = 80
      instance_families = ["m5", "m6i"]
    }
  }
}

run "default_ami_family" {
  command = plan

  assert {
    condition     = var.ami_family == "Bottlerocket"
    error_message = "Default AMI family should be Bottlerocket for Cilium CNI"
  }
}

run "creates_nodepool_when_enabled" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.node_pool) == 1
    error_message = "Should create 1 NodePool when enabled"
  }
}

run "creates_ec2_nodeclass" {
  command = plan

  assert {
    condition     = length(kubernetes_manifest.ec2_node_class) == 1
    error_message = "Should create 1 EC2NodeClass"
  }
}
