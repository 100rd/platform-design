# Tests for aws-eks-gpu-nodepools. kubernetes provider mocked (NodePool/EC2NodeClass
# are kubernetes_manifest in the wrapped module). Module default-OFF.
mock_provider "kubernetes" {}

variables {
  cluster_name       = "aws-eks-gpu-test"
  node_iam_role_name = "aws-eks-gpu-node"
  additional_node_tags = {
    "platform:owner" = "team-ml-platform"
    "platform:env"   = "staging"
  }
}

run "default_off_creates_no_pools" {
  command = plan

  assert {
    condition     = length(local.nodepool_configs) == 0
    error_message = "No NodePool configs when enabled defaults to false (apply-gated)."
  }
}

run "gpu_pools_built_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(local.nodepool_configs) == 2
    error_message = "Default serving + training-efa pools must be built when enabled."
  }

  assert {
    condition     = local.nodepool_configs["serving"].spot_percentage == 100
    error_message = "Serving pool must be spot-first (ADR-0046 D3)."
  }

  assert {
    condition     = local.nodepool_configs["training-efa"].spot_percentage == 0
    error_message = "EFA training pool must NOT be spot (ADR-0046 D3 / ADR-0045 D5)."
  }

  assert {
    condition     = local.nodepool_configs["serving"].consolidation_policy == "WhenEmptyOrUnderutilized"
    error_message = "Serving pool must consolidate (scale-to-zero R1 guard, ADR-0046 D1/D3)."
  }
}

run "gpu_taint_applied" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.nodepool_configs["serving"].taints[0].key == "nvidia.com/gpu"
    error_message = "GPU pools must carry the nvidia.com/gpu NoSchedule taint."
  }

  assert {
    condition     = local.nodepool_configs["training-efa"].labels["efa.enabled"] == "true"
    error_message = "EFA training pool must be labeled efa.enabled=true."
  }
}

run "adr0028_tags" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.platform_tags["platform:system"] == "ml-platform"
    error_message = "platform:system must be ml-platform."
  }

  assert {
    condition     = local.platform_tags["platform:owner"] == "team-ml-platform"
    error_message = "Caller-supplied platform:owner must be merged."
  }
}
