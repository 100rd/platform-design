mock_provider "aws" {}

override_data {
  target = data.aws_iam_policy_document.bucket_policy
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.readwrite
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

override_data {
  target = data.aws_iam_policy_document.readonly
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

variables {
  bucket_name = "test-app-bucket"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "test-app-bucket"
    error_message = "S3 bucket name should match input"
  }
}

run "versioning_enabled_by_default" {
  command = plan

  assert {
    condition     = var.versioning_enabled == true
    error_message = "Versioning should be enabled by default"
  }
}

run "public_access_blocked" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls == true
    error_message = "Public ACLs should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_policy == true
    error_message = "Public policies should be blocked"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.ignore_public_acls == true
    error_message = "Public ACLs should be ignored"
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    error_message = "Public buckets should be restricted"
  }
}

run "force_destroy_disabled_by_default" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "Force destroy should be disabled by default"
  }
}

run "iam_policies_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.readwrite) == 1
    error_message = "Read-write IAM policy should be created by default"
  }

  assert {
    condition     = length(aws_iam_policy.readonly) == 1
    error_message = "Read-only IAM policy should be created by default"
  }
}

run "iam_policies_skipped_when_disabled" {
  command = plan

  variables {
    create_iam_policies = false
  }

  assert {
    condition     = length(aws_iam_policy.readwrite) == 0
    error_message = "Read-write IAM policy should not be created when disabled"
  }
}

run "logging_enabled_when_bucket_specified" {
  command = plan

  variables {
    logging_bucket_name = "my-log-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 1
    error_message = "Access logging should be enabled when logging bucket is specified"
  }
}

run "logging_disabled_when_no_bucket" {
  command = plan

  variables {
    logging_bucket_name = ""
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging should be disabled when no logging bucket is specified"
  }
}

run "tls_enforcement_policy" {
  command = plan

  assert {
    condition     = aws_s3_bucket_policy.this.bucket == aws_s3_bucket.this.id
    error_message = "Bucket policy enforcing TLS should be attached"
  }
}
