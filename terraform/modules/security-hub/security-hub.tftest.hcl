mock_provider "aws" {}

override_data {
  target = data.aws_region.current
  values = {
    name = "us-east-1"
  }
}

variables {
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "security_hub_enabled" {
  command = plan

  assert {
    condition     = aws_securityhub_account.this.auto_enable_controls == true
    error_message = "Security Hub auto-enable controls should be true"
  }
}

run "pci_dss_standard_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_securityhub_standards_subscription.pci_dss) == 1
    error_message = "PCI-DSS standard should be enabled by default"
  }
}

run "cis_standard_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_securityhub_standards_subscription.cis) == 1
    error_message = "CIS standard should be enabled by default"
  }
}

run "aws_foundational_standard_enabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_securityhub_standards_subscription.aws_foundational) == 1
    error_message = "AWS Foundational standard should be enabled by default"
  }
}

run "org_auto_enable_by_default" {
  command = plan

  assert {
    condition     = aws_securityhub_organization_configuration.this.auto_enable == true
    error_message = "Auto-enable for org members should be true by default"
  }
}

run "standards_can_be_disabled" {
  command = plan

  variables {
    enable_pci_dss_standard          = false
    enable_cis_standard              = false
    enable_aws_foundational_standard = false
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.pci_dss) == 0
    error_message = "PCI-DSS standard should be disabled when set to false"
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.cis) == 0
    error_message = "CIS standard should be disabled when set to false"
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.aws_foundational) == 0
    error_message = "AWS Foundational standard should be disabled when set to false"
  }
}
