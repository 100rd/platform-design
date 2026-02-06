# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Analysis DynamoDB Jobs Table -- Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a DynamoDB table for tracking GPU video analysis job metadata. Stores job
# state, video information, and result URLs with GSIs for querying by game ID and status.
#
# Schema:
#   Partition key: job_id (S)    -- Unique job identifier
#   Sort key:      timestamp (S) -- ISO-8601 job creation/update timestamp
#   GSI:           game-id-index (game_id + timestamp) -- Query jobs by game
#   GSI:           status-index  (status + timestamp)  -- Query jobs by processing status
#   TTL:           ttl           -- Auto-expire completed jobs after retention period
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/dynamodb"
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
  name         = "${local.environment}-${local.aws_region}-gpu-video-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"
  range_key    = "timestamp"

  attributes = [
    { name = "job_id", type = "S" },
    { name = "timestamp", type = "S" },
    { name = "game_id", type = "S" },
    { name = "status", type = "S" },
  ]

  global_secondary_indexes = [
    {
      name            = "game-id-index"
      hash_key        = "game_id"
      range_key       = "timestamp"
      projection_type = "ALL"
    },
    {
      name            = "status-index"
      hash_key        = "status"
      range_key       = "timestamp"
      projection_type = "ALL"
    },
  ]

  point_in_time_recovery = true
  ttl_attribute          = "ttl"
  create_iam_policies    = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "metadata"
    ManagedBy   = "terragrunt"
  }
}
