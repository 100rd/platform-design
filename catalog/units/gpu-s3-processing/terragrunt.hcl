# ---------------------------------------------------------------------------------------------------------------------
# GPU Processing Bucket — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Ephemeral S3 bucket for intermediate GPU processing artifacts (frames, tensors, partial results).
# Data expires after 7 days — this is scratch space, not long-term storage.
#
# Versioning is disabled because intermediate data is disposable and regenerable.
# force_destroy is enabled in non-production environments for easy teardown.
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
  bucket_name        = "${local.environment}-${local.aws_region}-gpu-processing"
  versioning_enabled = false
  force_destroy      = local.environment != "prod"

  lifecycle_rules = [
    {
      id              = "expire-ephemeral"
      prefix          = ""
      expiration_days = 7
    },
  ]

  create_iam_policies = true

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "processing"
    ManagedBy   = "terragrunt"
  }
}
