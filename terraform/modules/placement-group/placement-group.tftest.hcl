mock_provider "aws" {}

variables {
  placement_groups = {
    gpu-cluster = {
      name     = "gpu-cluster-pg"
      strategy = "cluster"
    }
  }
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_placement_group" {
  command = plan

  assert {
    condition     = length(aws_placement_group.this) == 1
    error_message = "Should create 1 placement group"
  }
}

run "correct_strategy" {
  command = plan

  assert {
    condition     = aws_placement_group.this["gpu-cluster"].strategy == "cluster"
    error_message = "Placement group strategy should be cluster"
  }
}

run "correct_name" {
  command = plan

  assert {
    condition     = aws_placement_group.this["gpu-cluster"].name == "gpu-cluster-pg"
    error_message = "Placement group name should match input"
  }
}
