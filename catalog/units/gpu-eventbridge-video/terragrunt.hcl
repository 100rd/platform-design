# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Upload EventBridge Rule — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Connects the raw video S3 bucket to the video jobs SQS queue via EventBridge.
# When a video file (.mp4, .avi, .mov, .mkv) is uploaded to the raw video bucket,
# EventBridge routes the event to the SQS queue for GPU pod consumption.
#
# Dependencies:
#   - gpu-s3-raw-video: provides the source bucket name and ARN
#   - gpu-sqs-video-jobs: provides the target queue ARN and URL
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/eventbridge-s3-sqs"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------------------------------------------------

dependency "s3_raw_video" {
  config_path = "../gpu-s3-raw-video"

  mock_outputs = {
    bucket_id  = "mock-staging-eu-west-3-gpu-raw-video"
    bucket_arn = "arn:aws:s3:::mock-staging-eu-west-3-gpu-raw-video"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "sqs_video_jobs" {
  config_path = "../gpu-sqs-video-jobs"

  mock_outputs = {
    queue_arn = "arn:aws:sqs:eu-west-3:123456789012:mock-staging-eu-west-3-gpu-video-jobs"
    queue_url = "https://sqs.eu-west-3.amazonaws.com/123456789012/mock-staging-eu-west-3-gpu-video-jobs"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name               = "${local.environment}-${local.aws_region}-gpu-video-upload"
  source_bucket_name = dependency.s3_raw_video.outputs.bucket_id
  source_bucket_arn  = dependency.s3_raw_video.outputs.bucket_arn
  target_queue_arn   = dependency.sqs_video_jobs.outputs.queue_arn
  target_queue_url   = dependency.sqs_video_jobs.outputs.queue_url

  event_pattern_suffix = [".mp4", ".avi", ".mov", ".mkv"]

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    ManagedBy   = "terragrunt"
  }
}
