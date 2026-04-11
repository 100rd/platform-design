mock_provider "aws" {}

variables {
  name                = "test-ram-share"
  transit_gateway_arn = "arn:aws:ec2:us-east-1:123456789012:transit-gateway/tgw-12345"
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "creates_tgw_ram_share" {
  command = plan

  assert {
    condition     = aws_ram_resource_share.tgw.name == "test-ram-share-tgw"
    error_message = "TGW RAM share should be created with correct name"
  }
}

run "share_with_organization_by_default" {
  command = plan

  assert {
    condition     = var.share_with_organization == true
    error_message = "Should share with organization by default"
  }
}

run "no_subnet_share_by_default" {
  command = plan

  assert {
    condition     = length(var.shared_subnet_arns) == 0
    error_message = "No subnet ARNs shared by default"
  }
}
