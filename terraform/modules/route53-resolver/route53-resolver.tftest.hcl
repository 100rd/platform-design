mock_provider "aws" {}

variables {
  name          = "test-resolver"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-aaa", "subnet-bbb"]
  allowed_cidrs = ["10.0.0.0/8"]
  tags = {
    Environment = "test"
    Team        = "network"
    ManagedBy   = "terraform"
  }
}

run "inbound_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_inbound == true
    error_message = "Inbound resolver should be enabled by default"
  }
}

run "outbound_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_outbound == true
    error_message = "Outbound resolver should be enabled by default"
  }
}

run "creates_inbound_endpoint" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_endpoint.inbound) == 1
    error_message = "Inbound endpoint should be created"
  }
}

run "creates_outbound_endpoint" {
  command = plan

  assert {
    condition     = length(aws_route53_resolver_endpoint.outbound) == 1
    error_message = "Outbound endpoint should be created"
  }
}
