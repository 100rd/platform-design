# ---------------------------------------------------------------------------------------------------------------------
# GPU Analysis ElastiCache Redis — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Redis cache for the video analysis pipeline. Provides:
#   - API response caching (heat map queries)
#   - Job metadata hot cache (reduces DynamoDB reads)
#   - Rate limiting counters
#   - WebSocket session state (future real-time features)
#
# Deployed in the GPU Analysis VPC database subnets with access restricted to
# the EKS cluster node security group.
#
# PCI-DSS: slow-log and engine-log shipped to CloudWatch (Req 10.1).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/elasticache"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name          = local.account_vars.locals.account_name
  aws_region            = local.region_vars.locals.aws_region
  environment           = local.account_vars.locals.environment
  video_pipeline_config = local.account_vars.locals.video_pipeline_config
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES: GPU VPC (subnets, SG) and GPU EKS (node SG for access)
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../gpu-vpc"

  mock_outputs = {
    vpc_id           = "vpc-00000000000000000"
    database_subnets = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "eks" {
  config_path = "../gpu-eks"

  mock_outputs = {
    node_security_group_id = "sg-00000000000000000"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name        = "${local.environment}-${local.aws_region}-gpu-video-cache"
  description = "Redis cache for GPU video analysis pipeline"

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.database_subnets

  allowed_security_group_ids = [dependency.eks.outputs.node_security_group_id]

  engine_version = try(local.video_pipeline_config.redis_engine_version, "7.1")
  node_type      = try(local.video_pipeline_config.redis_node_type, "cache.t4g.micro")
  num_cache_clusters = try(local.video_pipeline_config.redis_num_nodes, 2)

  transit_encryption_enabled = true
  snapshot_retention_limit   = 7

  # PCI-DSS logging
  slow_log_enabled   = true
  engine_log_enabled = true
  log_retention_days = 365

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "cache"
    ManagedBy   = "terragrunt"
  }
}
