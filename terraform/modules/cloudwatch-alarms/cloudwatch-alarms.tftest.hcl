mock_provider "aws" {}

variables {
  project     = "test-project"
  environment = "dev"
  alert_email = "alerts@example.com"
}

run "creates_sns_topic" {
  command = plan

  assert {
    condition     = aws_sns_topic.alerts.name == "test-project-dev-alerts"
    error_message = "SNS topic name should include project and environment"
  }
}

run "billing_alarm_disabled_by_default" {
  command = plan

  assert {
    condition     = var.enable_billing_alarm == false
    error_message = "Billing alarm should be disabled by default"
  }
}

run "creates_eks_api_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.eks_api_server_errors.alarm_name == "test-project-dev-eks-api-5xx"
    error_message = "EKS API alarm should include project and environment in name"
  }
}
