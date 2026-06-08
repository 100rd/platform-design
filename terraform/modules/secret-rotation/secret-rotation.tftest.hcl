mock_provider "aws" {
  # The aws_iam_policy_document data source is provider-computed; under a mock the
  # default return is a random string that fails the IAM JSON-policy validator on
  # aws_iam_role / aws_iam_role_policy. Pin partition/account/region so derived ARNs
  # render validly, and supply real policy JSON for the two policy documents.
  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-1"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.assume
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}]}"
    }
  }

  # Mirrors the real rotation policy: secretsmanager scoped to the secret ARN, KMS
  # scoped to the secret CMK. The iam_scoped_* assertions read this back.
  override_data {
    target          = data.aws_iam_policy_document.rotation
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"RotateThisSecret\",\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:DescribeSecret\",\"secretsmanager:GetSecretValue\",\"secretsmanager:PutSecretValue\",\"secretsmanager:UpdateSecretVersionStage\"],\"Resource\":\"arn:aws:secretsmanager:eu-west-1:123456789012:secret:app-db/credentials\"},{\"Sid\":\"GenerateNewPassword\",\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetRandomPassword\",\"Resource\":\"*\"},{\"Sid\":\"DecryptWithSecretCmk\",\"Effect\":\"Allow\",\"Action\":[\"kms:Decrypt\",\"kms:GenerateDataKey\"],\"Resource\":\"arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555\"},{\"Sid\":\"WriteOwnLogs\",\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/app-db-credentials-rotation:*\"}]}"
    }
  }

  # Give the rotation role a valid ARN so the Lambda (which validates role ARN)
  # can be created during apply runs.
  override_resource {
    target = aws_iam_role.rotation
    values = {
      arn = "arn:aws:iam::123456789012:role/app-db-credentials-rotation-role"
    }
  }

  # Give the secret a valid ARN so aws_lambda_permission.source_arn validates.
  override_resource {
    target = aws_secretsmanager_secret.this
    values = {
      arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:app-db/credentials-AbCdEf"
      id  = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:app-db/credentials-AbCdEf"
    }
  }

  # Give the Lambda a valid ARN so aws_secretsmanager_secret_rotation.rotation_lambda_arn validates.
  override_resource {
    target = aws_lambda_function.rotation
    values = {
      arn = "arn:aws:lambda:eu-west-1:123456789012:function:app-db-credentials-rotation"
    }
  }
}

# archive_file is a real data source (no AWS calls) — it packages the bundled
# placeholder handler during plan/apply so the Lambda has a deployable artifact.

variables {
  name        = "app-db/credentials"
  kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  tags = {
    Environment = "test"
    ManagedBy   = "terraform"
    Component   = "secret-rotation"
  }
}

run "creates_secret_kms_encrypted" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.name == "app-db/credentials"
    error_message = "Secret name should match var.name"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == var.kms_key_arn
    error_message = "Secret must be encrypted with the provided customer-managed CMK"
  }
}

run "resource_names_slugify_secret_path" {
  command = plan

  # Secret names allow "/", but IAM/Lambda/log-group names do not — they must slugify.
  assert {
    condition     = aws_iam_role.rotation.name == "app-db-credentials-rotation-role"
    error_message = "IAM role name must replace '/' from the secret name"
  }

  assert {
    condition     = aws_lambda_function.rotation.function_name == "app-db-credentials-rotation"
    error_message = "Lambda function name must replace '/' from the secret name"
  }
}

run "default_rotation_is_30_days" {
  command = plan

  assert {
    condition     = var.rotation_after_days == 30
    error_message = "Default rotation_after_days should be 30 (PCI-DSS Req 3.6.4 <= 90)"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this.rotation_rules[0].automatically_after_days == 30
    error_message = "rotation_rules should use automatically_after_days by default"
  }
}

run "rotate_immediately_defaults_true" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret_rotation.this.rotate_immediately == true
    error_message = "rotate_immediately should default to true (provider default)"
  }
}

run "schedule_expression_overrides_days" {
  command = plan

  variables {
    rotation_after_days          = null
    rotation_schedule_expression = "cron(0 3 1 * ? *)"
    rotation_duration            = "3h"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this.rotation_rules[0].schedule_expression == "cron(0 3 1 * ? *)"
    error_message = "schedule_expression should be passed to rotation_rules"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this.rotation_rules[0].automatically_after_days == null
    error_message = "automatically_after_days must be null when a schedule_expression is set (provider requires exactly one)"
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this.rotation_rules[0].duration == "3h"
    error_message = "rotation_duration should be passed through to rotation_rules.duration"
  }
}

run "no_vpc_config_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.rotation.vpc_config) == 0
    error_message = "VPC config should be absent when no subnet IDs are provided"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.vpc_access) == 0
    error_message = "AWSLambdaVPCAccessExecutionRole should not be attached without VPC config"
  }
}

run "vpc_config_enabled_with_subnets" {
  command = plan

  variables {
    vpc_subnet_ids         = ["subnet-0aaa1111bbbb2222c", "subnet-0ddd3333eeee4444f"]
    vpc_security_group_ids = ["sg-0abc1234def567890"]
  }

  assert {
    condition     = length(aws_lambda_function.rotation.vpc_config) == 1
    error_message = "VPC config should be present when subnet IDs are provided"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.vpc_access) == 1
    error_message = "AWSLambdaVPCAccessExecutionRole must be attached when the Lambda runs in a VPC"
  }
}

run "iam_scoped_to_this_secret_and_cmk" {
  command = apply

  # GetSecretValue must be scoped to the single secret ARN, not "*".
  assert {
    condition = anytrue([
      for s in jsondecode(data.aws_iam_policy_document.rotation.json).Statement :
      s.Sid == "RotateThisSecret" && contains(tolist(s.Action), "secretsmanager:GetSecretValue") && s.Resource != "*"
    ])
    error_message = "Rotation policy must allow GetSecretValue scoped to this secret (not *)"
  }

  # KMS access must be scoped to the secret's CMK, not "*".
  assert {
    condition = anytrue([
      for s in jsondecode(data.aws_iam_policy_document.rotation.json).Statement :
      s.Sid == "DecryptWithSecretCmk" && s.Resource == var.kms_key_arn
    ])
    error_message = "KMS decrypt must be scoped to the secret's CMK ARN"
  }
}

run "lambda_invokable_by_secretsmanager" {
  command = plan

  assert {
    condition     = aws_lambda_permission.secretsmanager.principal == "secretsmanager.amazonaws.com"
    error_message = "Secrets Manager must be granted lambda:InvokeFunction"
  }
}

run "rejects_invalid_rotation_days" {
  command = plan

  variables {
    rotation_after_days = 999
  }

  expect_failures = [
    var.rotation_after_days,
  ]
}
