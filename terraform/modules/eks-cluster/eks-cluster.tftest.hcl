# NOTE: The eks-cluster module wraps terraform-aws-modules/eks/aws and
# terraform-aws-modules/iam/aws which may have version-specific arguments
# incompatible with mock_provider plan evaluation.
# Tests are limited to variable-default validation.

mock_provider "aws" {}

variables {
  cluster_name = "test-eks-cluster"
  vpc_id       = "vpc-12345678"
  subnet_ids   = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "default_node_group_sizes" {
  command = plan

  assert {
    condition     = var.min_size == 3
    error_message = "Default min_size should be 3"
  }

  assert {
    condition     = var.max_size == 5
    error_message = "Default max_size should be 5"
  }

  assert {
    condition     = var.desired_size == 3
    error_message = "Default desired_size should be 3"
  }
}

run "public_endpoint_disabled_by_default" {
  command = plan

  assert {
    condition     = var.cluster_endpoint_public_access == false
    error_message = "Public endpoint should be disabled by default"
  }
}

run "all_log_types_enabled_by_default" {
  command = plan

  assert {
    condition     = length(var.cluster_enabled_log_types) == 5
    error_message = "All 5 control plane log types should be enabled for PCI-DSS"
  }

  assert {
    condition     = contains(var.cluster_enabled_log_types, "api")
    error_message = "API logs should be enabled"
  }

  assert {
    condition     = contains(var.cluster_enabled_log_types, "audit")
    error_message = "Audit logs should be enabled for PCI-DSS Req 10.2"
  }

  assert {
    condition     = contains(var.cluster_enabled_log_types, "authenticator")
    error_message = "Authenticator logs should be enabled"
  }
}

run "default_instance_types" {
  command = plan

  assert {
    condition     = contains(var.instance_types, "m5.large")
    error_message = "Default instance types should include m5.large"
  }
}

run "default_cluster_version" {
  command = plan

  assert {
    condition     = var.cluster_version == "1.29"
    error_message = "Default cluster version should be 1.29"
  }
}
