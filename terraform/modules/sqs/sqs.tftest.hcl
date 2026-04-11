mock_provider "aws" {}

variables {
  name = "test-queue"
  tags = {
    Environment = "test"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

run "creates_queue_with_correct_name" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.name == "test-queue"
    error_message = "Queue name should match input"
  }
}

run "sqs_managed_sse_enabled_by_default" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled == true
    error_message = "SQS-managed SSE should be enabled when no KMS key is provided"
  }
}

run "kms_encryption_when_key_provided" {
  command = plan

  variables {
    kms_master_key_id = "arn:aws:kms:us-east-1:123456789012:key/test-key"
  }

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/test-key"
    error_message = "KMS key should be set when provided"
  }
}

run "dlq_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_sqs_queue.dlq) == 1
    error_message = "Dead-letter queue should be created by default"
  }
}

run "dlq_not_created_when_disabled" {
  command = plan

  variables {
    create_dlq = false
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) == 0
    error_message = "Dead-letter queue should not be created when disabled"
  }
}

run "long_polling_enabled" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.receive_wait_time_seconds == 10
    error_message = "Long polling should be enabled with 10 second wait"
  }
}

run "iam_policies_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_policy.producer) == 1
    error_message = "Producer IAM policy should be created by default"
  }

  assert {
    condition     = length(aws_iam_policy.consumer) == 1
    error_message = "Consumer IAM policy should be created by default"
  }
}

run "default_visibility_timeout" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.visibility_timeout_seconds == 30
    error_message = "Default visibility timeout should be 30 seconds"
  }
}

run "not_fifo_by_default" {
  command = plan

  assert {
    condition     = aws_sqs_queue.this.fifo_queue == false
    error_message = "Queue should not be FIFO by default"
  }
}

run "dlq_retention_14_days" {
  command = plan

  assert {
    condition     = var.dlq_message_retention_seconds == 1209600
    error_message = "DLQ retention should be 14 days (1209600 seconds)"
  }
}
