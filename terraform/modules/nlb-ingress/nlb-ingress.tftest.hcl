mock_provider "aws" {}

variables {
  name              = "test-nlb"
  vpc_id            = "vpc-12345678"
  public_subnet_ids = ["subnet-aaa", "subnet-bbb"]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "NLB should be enabled by default"
  }
}

run "creates_nlb_when_enabled" {
  command = plan

  assert {
    condition     = length(aws_lb.this) == 1
    error_message = "NLB should be created when enabled"
  }
}

run "skips_nlb_when_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_lb.this) == 0
    error_message = "NLB should not be created when disabled"
  }
}
