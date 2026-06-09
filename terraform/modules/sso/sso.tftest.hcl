mock_provider "aws" {}

override_data {
  target = data.aws_ssoadmin_instances.this
  values = {
    arns               = ["arn:aws:sso:::instance/ssoins-1234567890abcdef"]
    identity_store_ids = ["d-1234567890"]
  }
}

variables {
  organization_id = "o-testorg12345"
  member_accounts = {}
  permission_sets = {}
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "empty_permission_sets_by_default" {
  command = plan

  assert {
    condition     = length(var.permission_sets) == 0
    error_message = "No permission sets should be defined by default"
  }
}

run "empty_member_accounts_by_default" {
  command = plan

  assert {
    condition     = length(var.member_accounts) == 0
    error_message = "No member accounts should be defined by default"
  }
}

run "empty_groups_by_default" {
  command = plan

  assert {
    condition     = length(var.groups) == 0
    error_message = "No groups should be defined by default"
  }
}

run "empty_assignments_by_default" {
  command = plan

  assert {
    condition     = length(var.assignments) == 0
    error_message = "No assignments should be defined by default"
  }
}

run "rejects_invalid_target_type" {
  command = plan

  variables {
    permission_sets = {
      ReadOnlyAccess = {
        description      = "Read-only"
        session_duration = "PT8H"
        managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      }
    }
    groups = { engineers = "Engineers" }
    assignments = [
      {
        group_key      = "engineers"
        permission_set = "ReadOnlyAccess"
        target_type    = "OU" # invalid — only ACCOUNT and AWS_ACCOUNT_ID allowed
        target_value   = "ou-xxxx-yyyyyyyy"
      }
    ]
  }

  expect_failures = [
    var.assignments,
  ]
}

run "verify_default_sso_lac_attributes" {
  command = plan

  assert {
    condition     = aws_ssoadmin_instance_access_control_attributes.this.instance_arn == "arn:aws:sso:::instance/ssoins-1234567890abcdef"
    error_message = "SSO Instance ARN mismatch on access control attributes resource"
  }

  assert {
    condition     = one(aws_ssoadmin_instance_access_control_attributes.this.attribute).key == "platform:system"
    error_message = "Attribute key platform:system is not mapped"
  }

  assert {
    condition     = one(one(one(aws_ssoadmin_instance_access_control_attributes.this.attribute).value).source) == "$${path:enterprise:user:department}"
    error_message = "Default attribute source mapping is incorrect"
  }
}

run "verify_custom_sso_lac_attributes" {
  command = plan

  variables {
    sso_lac_attribute_source = ["$${path:enterprise:user:title}"]
  }

  assert {
    condition     = one(one(one(aws_ssoadmin_instance_access_control_attributes.this.attribute).value).source) == "$${path:enterprise:user:title}"
    error_message = "Custom attribute source mapping was not applied"
  }
}
