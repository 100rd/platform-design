mock_provider "aws" {}

variables {
  name = "test-waf"
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "creates_web_acl" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.name == "test-waf"
    error_message = "WAF Web ACL name should match input"
  }
}

run "default_rate_limit" {
  command = plan

  assert {
    condition     = var.rate_limit == 2000
    error_message = "Default rate limit should be 2000"
  }
}

run "logging_configured" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.waf.name == "aws-waf-logs-test-waf"
    error_message = "WAF log group should follow naming convention"
  }
}
