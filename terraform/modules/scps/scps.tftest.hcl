mock_provider "aws" {}

variables {
  organization_id = "o-testorg12345"
  ou_ids = {
    Root    = "r-root"
    NonProd = "ou-nonprod"
    Prod    = "ou-prod"
  }
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "creates_deny_leave_org_policy" {
  command = plan

  assert {
    condition     = aws_organizations_policy.deny_leave_org.name == "platform-design-deny-leave-org"
    error_message = "Deny leave org policy should be created with project prefix"
  }
}

run "creates_deny_disable_cloudtrail_policy" {
  command = plan

  assert {
    condition     = aws_organizations_policy.deny_disable_cloudtrail.name == "platform-design-deny-disable-cloudtrail"
    error_message = "Deny disable CloudTrail policy should be created"
  }
}

run "creates_region_restriction_policy" {
  command = plan

  assert {
    condition     = aws_organizations_policy.restrict_regions.name == "platform-design-restrict-regions"
    error_message = "Region restriction policy should be created"
  }
}

run "default_allowed_regions_include_eu" {
  command = plan

  assert {
    condition     = contains(var.allowed_regions, "eu-west-1")
    error_message = "eu-west-1 should be in default allowed regions"
  }

  assert {
    condition     = contains(var.allowed_regions, "eu-central-1")
    error_message = "eu-central-1 should be in default allowed regions"
  }
}

run "workload_ous_default" {
  command = plan

  assert {
    condition     = contains(var.workload_ou_names, "NonProd")
    error_message = "NonProd should be a default workload OU"
  }

  assert {
    condition     = contains(var.workload_ou_names, "Prod")
    error_message = "Prod should be a default workload OU"
  }
}
