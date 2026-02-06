# ---------------------------------------------------------------------------------------------------------------------
# GPU Analysis Results Bucket — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# S3 bucket for final video analysis results (heat maps, player tracking data, statistics).
# Versioning is enabled to protect completed analysis outputs.
#
# Lifecycle tiering: INTELLIGENT_TIERING (30 days) -> GLACIER (365 days) for cost optimization
# on older results that are infrequently accessed but must be retained.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/s3-app"
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
  bucket_name        = "${local.environment}-${local.aws_region}-gpu-results"
  versioning_enabled = true

  lifecycle_rules = [
    {
      id     = "tiering"
      prefix = ""
      transitions = [
        {
          days          = 30
          storage_class = "INTELLIGENT_TIERING"
        },
        {
          days          = 365
          storage_class = "GLACIER"
        },
      ]
    },
  ]

  create_iam_policies = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "results"
    ManagedBy   = "terragrunt"
  }
}
