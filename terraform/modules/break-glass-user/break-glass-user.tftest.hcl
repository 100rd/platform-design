mock_provider "aws" {
  # Pin the partition / account so policy-document ARNs render as valid ARNs that
  # the IAM policy validators accept (the default mock returns random strings).
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "000000000000"
    }
  }

  # The iam_policy_document data source is provider-computed; the default mock
  # returns a random string that fails IAM's JSON-policy validator. Supply a
  # minimal valid policy document so the inline-policy resource validates.
  override_data {
    target = data.aws_iam_policy_document.mfa_enforcement
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Test\",\"Effect\":\"Deny\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    }
  }
}

variables {
  account_name = "management"
  name_prefix  = "platform-"
  tags = {
    Environment = "test"
    Team        = "security"
  }
}

run "user_name_follows_convention" {
  command = plan

  assert {
    condition     = aws_iam_user.this.name == "break-glass-management"
    error_message = "Break-glass user name must be break-glass-<account_name>"
  }

  assert {
    condition     = aws_iam_user.this.path == "/break-glass/"
    error_message = "Break-glass user must live under the /break-glass/ path"
  }
}

run "destroy_protection_guards_present" {
  command = plan

  # ADR-0011: apply-time backstop must be in place.
  assert {
    condition     = aws_iam_user.this.force_destroy == false
    error_message = "ADR-0011: break-glass user must set force_destroy = false"
  }
}

run "mfa_enforcement_policy_attached" {
  command = plan

  assert {
    condition     = aws_iam_user_policy.mfa_enforcement.name == "platform-break-glass-management-mfa-enforcement"
    error_message = "MFA enforcement inline policy should be created with the prefixed name"
  }
}

run "no_access_key_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_access_key.this) == 0
    error_message = "Access key must be opt-in (create_access_key defaults to false)"
  }
}

run "no_console_login_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_user_login_profile.this) == 0
    error_message = "Console login must be opt-in (create_console_login defaults to false)"
  }
}

run "access_key_created_when_requested" {
  command = plan

  variables {
    create_access_key = true
  }

  assert {
    condition     = length(aws_iam_access_key.this) == 1
    error_message = "Access key should be created when create_access_key = true"
  }
}

run "alarm_skipped_without_log_group" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.usage) == 0
    error_message = "Usage alarm must not be created when cloudtrail_log_group_name is empty"
  }
}

run "alarm_created_when_wired" {
  command = plan

  variables {
    cloudtrail_log_group_name = "/aws/cloudtrail/org-trail"
    alarm_sns_topic_arn       = "arn:aws:sns:eu-west-1:000000000000:security-alerts"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.usage) == 1
    error_message = "Usage alarm should be created when both log group and SNS topic are provided"
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.usage) == 1
    error_message = "Metric filter should be created when both log group and SNS topic are provided"
  }
}
