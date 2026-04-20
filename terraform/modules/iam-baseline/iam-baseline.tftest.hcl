mock_provider "aws" {}

variables {
  name_prefix = "test-"
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "password_length_exceeds_pci_minimum" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.minimum_password_length >= 7
    error_message = "Password length must be at least 7 per PCI-DSS Req 8.2.3"
  }

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.minimum_password_length == 14
    error_message = "Default password length should be 14 for defense in depth"
  }
}

run "password_complexity_requirements" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.require_lowercase_characters == true
    error_message = "Lowercase characters should be required"
  }

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.require_uppercase_characters == true
    error_message = "Uppercase characters should be required"
  }

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.require_numbers == true
    error_message = "Numbers should be required"
  }

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.require_symbols == true
    error_message = "Symbols should be required"
  }
}

run "password_expiry_pci_compliant" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.max_password_age <= 90
    error_message = "Password must expire within 90 days per PCI-DSS Req 8.2.4"
  }
}

run "password_reuse_prevention_pci_compliant" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.pci_dss.password_reuse_prevention >= 4
    error_message = "Must prevent reuse of at least 4 passwords per PCI-DSS Req 8.2.5"
  }
}

run "mfa_enforcement_policy_created" {
  command = plan

  assert {
    condition     = aws_iam_policy.enforce_mfa.name == "test-EnforceMFA"
    error_message = "MFA enforcement policy should be created with correct name prefix"
  }
}

run "access_analyzer_account_type_default" {
  command = plan

  assert {
    condition     = var.analyzer_type == "ACCOUNT"
    error_message = "Default analyzer type should be ACCOUNT"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.account) == 1
    error_message = "Account-type analyzer should be created by default"
  }
}

run "access_analyzer_organization_type" {
  command = plan

  variables {
    analyzer_type = "ORGANIZATION"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.org) == 1
    error_message = "Organization-type analyzer should be created when specified"
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.account) == 0
    error_message = "Account analyzer should not be created when organization type is selected"
  }
}

run "s3_public_access_block_enabled" {
  command = plan

  assert {
    condition     = aws_s3_account_public_access_block.this.block_public_acls == true
    error_message = "S3 account-level public access block should be enabled (CIS 2.1.5)"
  }
}

run "ebs_encryption_enabled" {
  command = plan

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled == true
    error_message = "EBS encryption by default should be enabled (CIS 2.2.1)"
  }
}

run "ebs_custom_kms_key_optional" {
  command = plan

  variables {
    ebs_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  }

  assert {
    condition     = length(aws_ebs_default_kms_key.this) == 1
    error_message = "Custom EBS KMS key should be set when ARN is provided"
  }
}
