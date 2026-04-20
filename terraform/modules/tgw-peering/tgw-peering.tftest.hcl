mock_provider "aws" {}
mock_provider "aws" {
  alias = "peer"
}

variables {
  name            = "test-peering"
  local_tgw_id    = "tgw-local-12345"
  peer_tgw_id     = "tgw-peer-67890"
  peer_region     = "eu-central-1"
  peer_account_id = "987654321098"
  local_route_table_ids = {
    shared = "tgw-rtb-aaa"
  }
  peer_cidrs = ["10.13.0.0/16"]
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_peering_when_enabled" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment.this) == 1
    error_message = "TGW peering attachment should be created when enabled"
  }
}

run "skips_peering_when_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_peering_attachment.this) == 0
    error_message = "TGW peering attachment should not be created when disabled"
  }
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "TGW peering should be enabled by default"
  }
}
