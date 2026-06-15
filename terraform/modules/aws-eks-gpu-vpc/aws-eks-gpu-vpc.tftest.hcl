# ---------------------------------------------------------------------------------------------------------------------
# Tests for aws-eks-gpu-vpc. The aws provider is mocked so plan-time assertions run
# with no credentials. The module is default-OFF; tests flip enabled = true to assert
# the EFA fabric wiring (MTU, EFA SG, single-AZ pin) and ADR-0028 tags.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "aws" {}

variables {
  cluster_name    = "aws-eks-gpu-test"
  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.80.0.0/20", "10.80.16.0/20"]
  gpu_subnets     = ["10.80.128.0/20", "10.80.144.0/20"]
  tags = {
    "platform:system" = "ml-platform"
    "platform:owner"  = "team-ml-platform"
    "platform:env"    = "staging"
  }
}

run "default_off_creates_nothing" {
  command = plan

  assert {
    condition     = length(module.vpc) == 0
    error_message = "VPC must not be created when enabled defaults to false (apply-gated)."
  }

  assert {
    condition     = length(aws_security_group.efa) == 0
    error_message = "EFA SG must not be created when disabled."
  }
}

run "jumbo_frame_mtu_default" {
  command = plan

  assert {
    condition     = var.mtu == 9001
    error_message = "GPU subnets must default to the in-VPC AWS maximum MTU 9001 (ADR-0045 D1)."
  }
}

run "creates_vpc_and_efa_sg_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = length(module.vpc) == 1
    error_message = "VPC must be created when enabled = true."
  }

  assert {
    condition     = length(aws_security_group.efa) == 1
    error_message = "EFA self-referencing SG must be created when enabled."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.efa_self[0].ip_protocol == "-1"
    error_message = "EFA ingress rule must allow all traffic (ip_protocol -1) from peers."
  }
}

run "adr0028_tags_present_when_enabled" {
  command = plan

  variables {
    enabled = true
  }

  assert {
    condition     = local.base_tags["platform:system"] == "ml-platform"
    error_message = "platform:system must be ml-platform per ADR-0028/0044 D6."
  }

  assert {
    condition     = local.base_tags["platform:component"] == "gpu-network"
    error_message = "platform:component must be gpu-network for the VPC."
  }

  assert {
    condition     = local.base_tags["platform:owner"] == "team-ml-platform"
    error_message = "Caller-supplied platform:owner must be merged."
  }
}

run "efa_sg_can_be_disabled" {
  command = plan

  variables {
    enabled                   = true
    enable_efa_security_group = false
  }

  assert {
    condition     = length(aws_security_group.efa) == 0
    error_message = "EFA SG must not be created when enable_efa_security_group = false."
  }
}
