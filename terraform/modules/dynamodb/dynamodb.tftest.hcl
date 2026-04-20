mock_provider "aws" {}

variables {
  name     = "test-table"
  hash_key = "pk"
  attributes = [
    { name = "pk", type = "S" }
  ]
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_table_with_correct_name" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.name == "test-table"
    error_message = "Table name should match input"
  }
}

run "pay_per_request_by_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "Default billing mode should be PAY_PER_REQUEST"
  }
}

run "server_side_encryption_enabled" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].enabled == true
    error_message = "Server-side encryption should be enabled"
  }
}

run "pitr_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].enabled == true
    error_message = "Point-in-time recovery should be enabled by default"
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
    error_message = "IAM policies should not be created when disabled"
  }
}

run "ttl_disabled_by_default" {
  command = plan

  assert {
    condition     = var.ttl_attribute == ""
    error_message = "TTL should be disabled by default"
  }
}

run "supports_gsi" {
  command = plan

  variables {
    attributes = [
      { name = "pk", type = "S" },
      { name = "gsi_pk", type = "S" }
    ]
    global_secondary_indexes = [
      {
        name     = "gsi-index"
        hash_key = "gsi_pk"
      }
    ]
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 1
    error_message = "Should support GSI creation"
  }
}
