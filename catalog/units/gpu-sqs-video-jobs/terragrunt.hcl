# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Processing Job Queue — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# SQS queue for GPU video analysis jobs. EventBridge routes S3 upload events from the
# raw video bucket into this queue. GPU pods consume messages via long polling.
#
# visibility_timeout is set to 1 hour to accommodate long-running GPU video analysis.
# Messages are retained for 14 days and moved to DLQ after 3 failed processing attempts.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/sqs"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name                       = "${local.environment}-${local.aws_region}-gpu-video-jobs"
  visibility_timeout_seconds = 3600
  message_retention_seconds  = 1209600
  receive_wait_time_seconds  = 20
  create_dlq                 = true
  max_receive_count          = 3
  create_iam_policies        = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    ManagedBy   = "terragrunt"
  }
}
