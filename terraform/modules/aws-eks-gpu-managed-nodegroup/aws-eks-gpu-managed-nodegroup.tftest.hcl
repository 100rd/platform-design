# Tests for aws-eks-gpu-managed-nodegroup. aws provider mocked; module default-OFF.
mock_provider "aws" {}

# The node trust policy is computed from an aws_iam_policy_document data source,
# which the mock provider cannot render. Override it with a valid policy JSON.
override_data {
  target = data.aws_iam_policy_document.node_assume[0]
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  cluster_name = "aws-eks-gpu-test"
  subnet_ids   = ["subnet-0gpu"]
  tags = {
    "platform:owner" = "team-ml-platform"
    "platform:env"   = "staging"
  }
}

run "default_off_creates_nothing" {
  command = plan

  assert {
    condition     = length(aws_eks_node_group.training) == 0
    error_message = "No node group when enabled defaults to false (apply-gated)."
  }
}

run "creates_node_group_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(aws_eks_node_group.training) == 1
    error_message = "Managed node group must be created when enabled (ADR-0046 D2)."
  }

  assert {
    condition     = aws_eks_node_group.training[0].capacity_type == "ON_DEMAND"
    error_message = "EFA training must default to ON_DEMAND, never spot (ADR-0046 A4)."
  }
}

run "spot_rejected" {
  command = plan

  variables {
    enabled       = true
    capacity_type = "SPOT"
  }

  expect_failures = [var.capacity_type]
}

run "capacity_block_supported" {
  command = plan

  variables {
    enabled                       = true
    capacity_type                 = "CAPACITY_BLOCK"
    capacity_block_reservation_id = "cr-0123456789abcdef0"
  }

  assert {
    condition     = aws_eks_node_group.training[0].capacity_type == "CAPACITY_BLOCK"
    error_message = "Capacity Block must be supported for scarce EFA families (ADR-0046 D4)."
  }
}

run "efa_dra_mode_default" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.base_tags["platform:efa-mode"] == "dra"
    error_message = "Managed node groups use the EFA DRA mode (ADR-0045 D3)."
  }

  assert {
    condition     = local.base_tags["platform:system"] == "ml-platform"
    error_message = "platform:system must be ml-platform (ADR-0028)."
  }
}
