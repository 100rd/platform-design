mock_provider "aws" {}

variables {
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "detector_enabled" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this.enable == true
    error_message = "GuardDuty detector should be enabled"
  }
}

run "fifteen_minute_publishing_frequency" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this.finding_publishing_frequency == "FIFTEEN_MINUTES"
    error_message = "Finding publishing frequency should be 15 minutes"
  }
}

run "s3_protection_enabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_s3_protection == true
    error_message = "S3 protection should be enabled by default"
  }
}

run "eks_audit_log_monitoring_enabled" {
  command = plan

  assert {
    condition     = var.enable_eks_audit_log_monitoring == true
    error_message = "EKS audit log monitoring should be enabled by default"
  }
}

run "eks_runtime_monitoring_enabled" {
  command = plan

  assert {
    condition     = var.enable_eks_runtime_monitoring == true
    error_message = "EKS runtime monitoring should be enabled by default"
  }
}

run "malware_protection_enabled" {
  command = plan

  assert {
    condition     = var.enable_malware_protection == true
    error_message = "Malware protection should be enabled by default"
  }
}

run "rds_protection_enabled" {
  command = plan

  assert {
    condition     = var.enable_rds_protection == true
    error_message = "RDS protection should be enabled by default"
  }
}

run "lambda_protection_enabled" {
  command = plan

  assert {
    condition     = var.enable_lambda_protection == true
    error_message = "Lambda protection should be enabled by default"
  }
}

run "auto_enable_org_members_by_default" {
  command = plan

  assert {
    condition     = aws_guardduty_organization_configuration.this.auto_enable_organization_members == "ALL"
    error_message = "Auto-enable for organization members should be set to ALL"
  }
}

run "detector_tagged_for_pci_dss" {
  command = plan

  assert {
    condition     = aws_guardduty_detector.this.tags["pci-dss-scope"] == "true"
    error_message = "Detector should be tagged as PCI-DSS scoped"
  }
}

run "no_delegated_admin_by_default" {
  command = plan

  assert {
    condition     = length(aws_guardduty_organization_admin_account.this) == 0
    error_message = "Delegated admin should not be created when account ID matches current"
  }
}
