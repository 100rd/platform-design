mock_provider "aws" {}

variables {
  name               = "test-attachment"
  transit_gateway_id = "tgw-12345"
  vpc_id             = "vpc-12345"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  route_table_id     = "tgw-rtb-12345"
  vpc_route_table_ids = ["rtb-aaa", "rtb-bbb"]
  tgw_destination_cidr = "10.0.0.0/8"
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_attachment_when_enabled" {
  command = plan

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.this) == 1
    error_message = "TGW VPC attachment should be created when enabled"
  }
}

run "skips_attachment_when_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.this) == 0
    error_message = "TGW VPC attachment should not be created when disabled"
  }
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "TGW attachment should be enabled by default"
  }
}
