mock_provider "aws" {}

variables {
  s3_bucket_name = "test-config-bucket"
  tags = {
    Environment = "test"
    Team        = "security"
    ManagedBy   = "terraform"
  }
}

run "creates_config_recorder" {
  command = plan

  assert {
    condition     = aws_config_configuration_recorder.this.name == "default"
    error_message = "Config recorder should use default name"
  }
}

run "s3_bucket_created" {
  command = plan

  assert {
    condition     = aws_s3_bucket.config.bucket == "test-config-bucket"
    error_message = "Config S3 bucket name should match input"
  }
}

run "default_snapshot_frequency" {
  command = plan

  assert {
    condition     = var.snapshot_delivery_frequency == "TwentyFour_Hours"
    error_message = "Default snapshot delivery frequency should be TwentyFour_Hours"
  }
}
