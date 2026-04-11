mock_provider "aws" {}

variables {
  node_security_group_id = "sg-12345678"
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "ClusterMesh SG rules should be enabled by default"
  }
}

run "no_peer_cidrs_by_default" {
  command = plan

  assert {
    condition     = length(var.peer_vpc_cidrs) == 0
    error_message = "No peer VPC CIDRs should be defined by default"
  }
}
