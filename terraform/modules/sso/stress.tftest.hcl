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

run "verify_special_char_sso_lac_attributes" {
  command = plan

  variables {
    sso_lac_attribute_source = ["$${path:enterprise:user:department}", "custom-tag_with_special!@#%^&*()_+{}|:\"<>?`-=[]\\;',./"]
  }

  assert {
    condition     = length(one(one(aws_ssoadmin_instance_access_control_attributes.this.attribute).value).source) == 2
    error_message = "Should handle multiple custom source paths and special characters"
  }
}

run "verify_multiple_items_sso_lac_attributes" {
  command = plan

  variables {
    sso_lac_attribute_source = ["$${path:enterprise:user:department}", "$${path:enterprise:user:title}"]
  }

  assert {
    condition     = length(one(one(aws_ssoadmin_instance_access_control_attributes.this.attribute).value).source) == 2
    error_message = "Should allow multiple items in the list"
  }
}

run "rejects_invalid_account_short_name" {
  command = plan

  variables {
    permission_sets = {
      ReadOnlyAccess = {
        description      = "Read-only"
        session_duration = "PT8H"
        managed_policies = []
      }
    }
    groups = { engineers = "Engineers" }
    assignments = [
      {
        group_key      = "engineers"
        permission_set = "ReadOnlyAccess"
        target_type    = "ACCOUNT"
        target_value   = "unknown-acct"
      }
    ]
  }

  expect_failures = [
    aws_ssoadmin_account_assignment.this
  ]
}

run "rejects_undefined_permission_set" {
  command = plan

  variables {
    member_accounts = {
      main = {
        account_id = "123456789012"
        email      = "main@test.org"
        ou         = "Root"
      }
    }
    groups = { engineers = "Engineers" }
    assignments = [
      {
        group_key      = "engineers"
        permission_set = "UndefinedAccess"
        target_type    = "ACCOUNT"
        target_value   = "main"
      }
    ]
  }

  expect_failures = [
    aws_ssoadmin_account_assignment.this
  ]
}

run "rejects_undefined_group_key" {
  command = plan

  variables {
    member_accounts = {
      main = {
        account_id = "123456789012"
        email      = "main@test.org"
        ou         = "Root"
      }
    }
    permission_sets = {
      ReadOnlyAccess = {
        description      = "Read-only"
        session_duration = "PT8H"
        managed_policies = []
      }
    }
    assignments = [
      {
        group_key      = "engineers"
        permission_set = "ReadOnlyAccess"
        target_type    = "ACCOUNT"
        target_value   = "main"
      }
    ]
  }

  expect_failures = [
    aws_ssoadmin_account_assignment.this
  ]
}

run "verify_empty_sso_lac_attributes" {
  command = plan

  variables {
    sso_lac_attribute_source = []
  }
}
