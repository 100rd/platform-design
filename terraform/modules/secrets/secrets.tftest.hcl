mock_provider "aws" {}

variables {
  secrets = {
    "db/password" = {
      description = "Database password"
    }
  }
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_secret" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret.secrets) == 1
    error_message = "Should create 1 secret"
  }

  assert {
    condition     = aws_secretsmanager_secret.secrets["db/password"].name == "db/password"
    error_message = "Secret name should match key"
  }
}

run "rotation_not_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.rotation) == 0
    error_message = "Rotation should not be created by default"
  }
}

run "rotation_created_when_enabled" {
  command = plan

  variables {
    secrets = {
      "db/password" = {
        description     = "Database password"
        enable_rotation = true
      }
    }
    rotation_lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:rotate-secret"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.rotation) == 1
    error_message = "Rotation should be created when enabled with Lambda ARN"
  }
}

run "default_rotation_period" {
  command = plan

  assert {
    condition     = var.rotation_days == 90
    error_message = "Default rotation period should be 90 days per PCI-DSS Req 3.6.4"
  }
}

run "kms_encryption_optional" {
  command = plan

  variables {
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  }

  assert {
    condition     = aws_secretsmanager_secret.secrets["db/password"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/test-key"
    error_message = "KMS key should be set when provided"
  }
}

run "multiple_secrets_supported" {
  command = plan

  variables {
    secrets = {
      "db/password" = {
        description = "Database password"
      }
      "api/key" = {
        description = "API key"
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.secrets) == 2
    error_message = "Should create 2 secrets"
  }
}
