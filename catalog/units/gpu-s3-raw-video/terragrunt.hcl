# ---------------------------------------------------------------------------------------------------------------------
# GPU Raw Video Upload Bucket — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# S3 bucket for raw sport video uploads before GPU processing.
# Lifecycle tiering: INTELLIGENT_TIERING (1 day) -> GLACIER (90 days) -> DEEP_ARCHIVE (180 days).
#
# EventBridge notifications on this bucket trigger the video processing pipeline via SQS.
# IAM policies are created for IRSA-based pod access.
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
  bucket_name        = "${local.environment}-${local.aws_region}-gpu-raw-video"
  versioning_enabled = true

  lifecycle_rules = [
    {
      id     = "tiering"
      prefix = ""
      transitions = [
        {
          days          = 1
          storage_class = "INTELLIGENT_TIERING"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        },
        {
          days          = 180
          storage_class = "DEEP_ARCHIVE"
        },
      ]
    },
  ]

  create_iam_policies = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "raw"
    ManagedBy   = "terragrunt"
  }
}
