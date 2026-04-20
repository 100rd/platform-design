mock_provider "aws" {}

variables {
  project     = "test-project"
  environment = "dev"
}

run "enabled_by_default" {
  command = plan

  assert {
    condition     = var.enabled == true
    error_message = "Auto-shutdown should be enabled by default"
  }
}

run "lambda_created_when_enabled" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.auto_shutdown) == 1
    error_message = "Lambda function should be created when enabled"
  }
}

run "lambda_not_created_when_disabled" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(aws_lambda_function.auto_shutdown) == 0
    error_message = "Lambda function should not be created when disabled"
  }
}

run "default_shutdown_schedule" {
  command = plan

  assert {
    condition     = var.shutdown_schedule == "cron(0 19 ? * MON-FRI *)"
    error_message = "Default shutdown should be Mon-Fri 19:00 UTC"
  }
}

run "default_startup_schedule" {
  command = plan

  assert {
    condition     = var.startup_schedule == "cron(30 7 ? * MON-FRI *)"
    error_message = "Default startup should be Mon-Fri 07:30 UTC"
  }
}
