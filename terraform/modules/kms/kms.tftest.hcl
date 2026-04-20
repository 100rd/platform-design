mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_iam_policy_document.key_policy["eks"]
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  environment = "dev"
  keys = {
    eks = {
      description = "KMS key for EKS secrets encryption"
      admin_arns  = ["arn:aws:iam::123456789012:role/admin"]
      user_arns   = ["arn:aws:iam::123456789012:role/eks-node"]
    }
  }
  tags = {
    Environment = "dev"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_kms_key_with_rotation" {
  command = plan

  assert {
    condition     = aws_kms_key.this["eks"].enable_key_rotation == true
    error_message = "KMS key rotation must be enabled for PCI-DSS compliance"
  }
}

run "creates_kms_alias" {
  command = plan

  assert {
    condition     = aws_kms_alias.this["eks"].name == "alias/dev/eks"
    error_message = "KMS alias should follow alias/{environment}/{key_name} format"
  }
}

run "key_tagged_with_pci_scope" {
  command = plan

  assert {
    condition     = aws_kms_key.this["eks"].tags["pci-dss-scope"] == "true"
    error_message = "KMS key should be tagged as PCI-DSS scoped"
  }

  assert {
    condition     = aws_kms_key.this["eks"].tags["key-purpose"] == "eks"
    error_message = "KMS key should have key-purpose tag"
  }
}

run "environment_validation_passes" {
  command = plan

  variables {
    environment = "prod"
  }

  assert {
    condition     = var.environment == "prod"
    error_message = "prod should be a valid environment"
  }
}

run "deletion_window_default_30_days" {
  command = plan

  assert {
    condition     = aws_kms_key.this["eks"].deletion_window_in_days == 30
    error_message = "Default deletion window should be 30 days"
  }
}

run "key_usage_default_encrypt_decrypt" {
  command = plan

  assert {
    condition     = aws_kms_key.this["eks"].key_usage == "ENCRYPT_DECRYPT"
    error_message = "Default key usage should be ENCRYPT_DECRYPT"
  }
}

run "multiple_keys_supported" {
  command = plan

  override_data {
    target = data.aws_iam_policy_document.key_policy["eks"]
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.key_policy["rds"]
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  variables {
    keys = {
      eks = {
        description = "EKS key"
        admin_arns  = ["arn:aws:iam::123456789012:role/admin"]
        user_arns   = ["arn:aws:iam::123456789012:role/eks"]
      }
      rds = {
        description = "RDS key"
        admin_arns  = ["arn:aws:iam::123456789012:role/admin"]
        user_arns   = ["arn:aws:iam::123456789012:role/rds"]
      }
    }
  }

  assert {
    condition     = length(aws_kms_key.this) == 2
    error_message = "Should create 2 KMS keys"
  }
}
