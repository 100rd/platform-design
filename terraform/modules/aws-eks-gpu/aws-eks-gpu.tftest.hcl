# Tests for aws-eks-gpu. aws provider mocked; module is default-OFF.
#
# The upstream terraform-aws-modules/eks module computes its IAM trust policy from
# aws_iam_policy_document data sources, which the mock provider cannot render to
# valid JSON. We override those data sources with a minimal valid policy so the
# plan-time wiring assertions can run without credentials or a live cluster.
mock_provider "aws" {
  # Force a real AWS partition so the upstream EKS module builds valid policy ARNs
  # (arn:aws:iam::aws:policy/...) instead of a random mock partition.
  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      id                 = "aws"
      reverse_dns_prefix = "com.amazonaws"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
      arn        = "arn:aws:iam::111122223333:role/test"
      user_id    = "AIDACKCEVSQ6C2EXAMPLE"
      id         = "111122223333"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = {
      arn          = "arn:aws:iam::111122223333:role/test"
      issuer_arn   = "arn:aws:iam::111122223333:role/test"
      issuer_id    = "AIDACKCEVSQ6C2EXAMPLE"
      issuer_name  = "test"
      session_name = ""
      id           = "arn:aws:iam::111122223333:role/test"
    }
  }
}

override_data {
  target = module.eks[0].data.aws_iam_policy_document.assume_role_policy[0]
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = module.eks[0].data.aws_iam_policy_document.node_assume_role_policy[0]
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  cluster_name = "aws-eks-gpu-test"
  vpc_id       = "vpc-0123456789abcdef0"
  subnet_ids   = ["subnet-0a", "subnet-0b"]
  tags = {
    "platform:owner" = "team-ml-platform"
    "platform:env"   = "staging"
  }
}

run "default_off_creates_no_cluster" {
  command = plan

  assert {
    condition     = length(module.eks) == 0
    error_message = "EKS cluster must not be created when enabled defaults to false (apply-gated)."
  }
}

run "creates_cluster_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(module.eks) == 1
    error_message = "EKS cluster must be created when enabled = true."
  }
}

run "dra_version_floor_enforced" {
  command = plan

  variables {
    cluster_version = "1.30"
  }

  expect_failures = [var.cluster_version]
}

run "adr0028_tags_and_dra_marker" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.base_tags["platform:system"] == "ml-platform"
    error_message = "platform:system must be ml-platform (ADR-0044 D6)."
  }

  assert {
    condition     = local.base_tags["platform:component"] == "gpu-compute"
    error_message = "platform:component must be gpu-compute."
  }

  assert {
    condition     = local.base_tags["platform:dra-feature-gate"] == "enabled"
    error_message = "DRA feature-gate conformance marker must be present (ADR-0044 D2)."
  }
}
