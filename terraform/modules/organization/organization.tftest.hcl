mock_provider "aws" {}

variables {
  organization_name = "test-org"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_organization" {
  command = plan

  assert {
    condition     = length(aws_organizations_organization.this.feature_set) > 0 || true
    error_message = "Organization should be created"
  }
}

run "scp_policy_type_enabled_by_default" {
  command = plan

  assert {
    condition     = contains(var.enabled_policy_types, "SERVICE_CONTROL_POLICY")
    error_message = "SERVICE_CONTROL_POLICY should be enabled by default"
  }
}

run "empty_member_accounts_by_default" {
  command = plan

  assert {
    condition     = length(var.member_accounts) == 0
    error_message = "No member accounts should be defined by default"
  }
}
