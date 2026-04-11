mock_provider "aws" {}

variables {
  name = "test-tgw"
  route_tables = {
    shared   = "shared-rt"
    nonprod  = "nonprod-rt"
    prod     = "prod-rt"
  }
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_transit_gateway" {
  command = plan

  assert {
    condition     = aws_ec2_transit_gateway.this.description == "test-tgw"
    error_message = "Transit gateway description should match name"
  }
}

run "default_asn" {
  command = plan

  assert {
    condition     = var.amazon_side_asn == 64512
    error_message = "Default Amazon-side ASN should be 64512"
  }
}

run "route_tables_created" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_route_table.this) == 3
    error_message = "Should create 3 route tables"
  }
}

run "multicast_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_multicast == false
    error_message = "Multicast should be disabled by default"
  }
}
