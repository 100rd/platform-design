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

run "creates_eks_cluster_with_defaults" {
  command = plan

  assert {
    condition     = module.eks.cluster_name == "test-eks"
    error_message = "EKS cluster name should match input"
  }

  assert {
    condition     = module.eks.cluster_version == "1.32"
    error_message = "Kubernetes version should be 1.32"
  }
}

run "private_endpoint_always_enabled" {
  command = plan

  assert {
    condition     = module.eks.cluster_endpoint_private_access == true
    error_message = "Private endpoint should always be enabled"
  }
}

run "public_endpoint_disabled_by_default" {
  command = plan

  assert {
    condition     = module.eks.cluster_endpoint_public_access == false
    error_message = "Public endpoint should be disabled by default"
  }
}

run "irsa_enabled" {
  command = plan

  assert {
    condition     = module.eks.enable_irsa == true
    error_message = "IRSA should be enabled"
  }
}

run "authentication_mode_correct" {
  command = plan

  assert {
    condition     = module.eks.authentication_mode == "API_AND_CONFIG_MAP"
    error_message = "Authentication mode should be API_AND_CONFIG_MAP"
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

run "kms_encryption_optional" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  }

  assert {
    condition     = module.eks.cluster_encryption_config != {}
    error_message = "Cluster encryption config should be set when KMS key is provided"
  }
}

run "bottlerocket_used_with_cilium" {
  command = plan

  variables {
    enable_vpc_cni = false
  }

  assert {
    condition     = module.eks.eks_managed_node_groups["system"]["ami_type"] == "BOTTLEROCKET_x86_64"
    error_message = "Bottlerocket should be used when Cilium CNI is selected"
  }
}

run "al2023_used_with_vpc_cni" {
  command = plan

  variables {
    enable_vpc_cni = true
  }

  assert {
    condition     = module.eks.eks_managed_node_groups["system"]["ami_type"] == "AL2023_x86_64_STANDARD"
    error_message = "AL2023 should be used when VPC CNI is selected"
  }
}

run "karpenter_submodule_configured" {
  command = plan

  assert {
    condition     = module.karpenter.enable_pod_identity == true
    error_message = "Karpenter Pod Identity should be enabled"
  }

  assert {
    condition     = module.karpenter.enable_spot_termination == true
    error_message = "Karpenter spot termination handling should be enabled"
  }
}
