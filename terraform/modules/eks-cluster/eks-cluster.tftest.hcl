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

run "creates_cluster_with_correct_version" {
  command = plan

  assert {
    condition     = module.eks.cluster_version == var.cluster_version
    error_message = "Cluster version should match input variable"
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

run "private_endpoint_always_enabled" {
  command = plan

  assert {
    condition     = module.eks.cluster_endpoint_private_access == true
    error_message = "Private endpoint access should always be enabled"
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

run "dns_sync_irsa_creates_policy" {
  command = plan

  assert {
    condition     = aws_iam_policy.dns_sync_policy.name == "test-eks-cluster-dns-sync-policy"
    error_message = "DNS sync policy should be named with cluster name prefix"
  }
}

run "failover_controller_irsa_creates_policy" {
  command = plan

  assert {
    condition     = aws_iam_policy.failover_controller_policy.name == "test-eks-cluster-failover-controller-policy"
    error_message = "Failover controller policy should be named with cluster name prefix"
  }
}

run "external_secrets_policy_created" {
  command = plan

  assert {
    condition     = aws_iam_policy.external_secrets_policy.name == "test-eks-cluster-external-secrets-policy"
    error_message = "External secrets policy should be named with cluster name prefix"
  }
}
