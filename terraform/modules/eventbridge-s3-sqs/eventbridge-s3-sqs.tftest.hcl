mock_provider "aws" {}

variables {
  name               = "test-event-rule"
  source_bucket_name = "test-source-bucket"
  source_bucket_arn  = "arn:aws:s3:::test-source-bucket"
  target_queue_arn   = "arn:aws:sqs:us-east-1:123456789012:test-queue"
  target_queue_url   = "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue"
}

run "creates_event_rule" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_rule.this.name == "test-event-rule"
    error_message = "EventBridge rule name should match input"
  }
}

run "default_video_suffixes" {
  command = plan

  assert {
    condition     = contains(var.event_pattern_suffix, ".mp4")
    error_message = "Default suffixes should include .mp4"
  }
}
