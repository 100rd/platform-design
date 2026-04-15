mock_provider "aws" {}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_partition.current
  values = {
    partition = "aws"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    name = "us-east-1"
  }
}

override_data {
  target = data.aws_iam_policy_document.cloudtrail_s3
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  trail_name      = "test-org-trail"
  organization_id = "o-testorg12345"
  kms_key_arn     = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  s3_bucket_name  = "test-cloudtrail-logs"
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "creates_organization_trail" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org_trail.is_organization_trail == true
    error_message = "Trail should be an organization trail"
  }

  assert {
    condition     = aws_cloudtrail.org_trail.is_multi_region_trail == true
    error_message = "Trail should be multi-region"
  }
}

run "log_file_validation_enabled" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org_trail.enable_log_file_validation == true
    error_message = "Log file validation must be enabled for PCI-DSS Req 10.5.5"
  }
}

run "kms_encryption_configured" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org_trail.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/test-key"
    error_message = "KMS encryption should be configured for PCI-DSS Req 10.5"
  }
}

run "s3_public_access_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.cloudtrail.block_public_acls == true
    error_message = "Public ACLs should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.cloudtrail.block_public_policy == true
    error_message = "Public policies should be blocked"
  }
}

run "cloudwatch_log_group_created" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.cloudtrail.name == "/aws/cloudtrail/test-org-trail"
    error_message = "CloudWatch log group name should follow naming convention"
  }

  assert {
    condition     = aws_cloudwatch_log_group.cloudtrail.retention_in_days == 365
    error_message = "CloudWatch log group retention should be 365 days"
  }
}

run "global_service_events_included" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org_trail.include_global_service_events == true
    error_message = "Global service events should be included"
  }
}

run "lifecycle_expiration_pci_compliant" {
  command = plan

  assert {
    condition     = var.lifecycle_expiration_days >= 365
    error_message = "Lifecycle expiration must be at least 365 days for PCI-DSS Req 10.7"
  }
}

run "trail_tagged_for_pci_dss" {
  command = plan

  assert {
    condition     = aws_cloudtrail.org_trail.tags["pci-dss-scope"] == "true"
    error_message = "Trail should be tagged as PCI-DSS scoped"
  }

  assert {
    condition     = aws_cloudtrail.org_trail.tags["Compliance"] == "pci-dss-req-10"
    error_message = "Trail should have compliance tag"
  }
}
