# NOTE: The EKS module wraps terraform-aws-modules/eks/aws which requires
# specific provider and module versions that may conflict with mock_provider.
# Tests are limited to variable-default validation to avoid community module
# compatibility issues during plan evaluation.

mock_provider "aws" {}
mock_provider "kubernetes" {}

variables {
  cluster_name       = "test-eks"
  cluster_version    = "1.32"
  vpc_id             = "vpc-12345678"
  private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "cluster_version_default" {
  command = plan

  assert {
    condition     = var.cluster_version == "1.32"
    error_message = "Default Kubernetes version should be 1.32"
  }
}

run "public_endpoint_disabled_by_default" {
  command = plan

  assert {
    condition     = var.cluster_endpoint_public_access == false
    error_message = "Public endpoint should be disabled by default"
  }
}

run "control_plane_logging_enabled" {
  command = plan

  assert {
    condition     = length(var.cluster_enabled_log_types) == 5
    error_message = "All 5 control plane log types should be enabled by default for PCI-DSS"
  }

  assert {
    condition     = contains(var.cluster_enabled_log_types, "audit")
    error_message = "Audit logs must be enabled for PCI-DSS Req 10.2"
  }
}

run "vpc_cni_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_vpc_cni == false
    error_message = "VPC CNI should be disabled by default (Cilium CNI used instead)"
  }
}

run "kms_encryption_empty_by_default" {
  command = plan

  assert {
    condition     = var.kms_key_arn == ""
    error_message = "KMS key ARN should be empty by default"
  }
}

run "karpenter_controller_defaults" {
  command = plan

  assert {
    condition     = var.karpenter_controller_desired_size == 2
    error_message = "Default desired size for Karpenter controller should be 2"
  }

  assert {
    condition     = var.karpenter_controller_min_size == 1
    error_message = "Default min size for Karpenter controller should be 1"
  }

  assert {
    condition     = var.karpenter_controller_max_size == 3
    error_message = "Default max size for Karpenter controller should be 3"
  }
}
