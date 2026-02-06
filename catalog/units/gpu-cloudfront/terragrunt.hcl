# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Analysis CloudFront CDN -- Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a CloudFront distribution with S3 origin for delivering heat map results
# to end users. Uses Origin Access Control (OAC) for secure S3 access and geo-restricts
# delivery to European countries.
#
# The distribution fronts the gpu-s3-results bucket and enforces HTTPS with the managed
# CachingOptimized cache policy. A 403-to-404 error mapping prevents bucket enumeration.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/cloudfront-s3"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GPU S3 Results Bucket
# ---------------------------------------------------------------------------------------------------------------------

dependency "s3_results" {
  config_path = "../gpu-s3-results"

  mock_outputs = {
    bucket_id          = "mock-gpu-results-bucket"
    bucket_arn         = "arn:aws:s3:::mock-gpu-results-bucket"
    bucket_domain_name = "mock-gpu-results-bucket.s3.eu-west-3.amazonaws.com"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name                           = "${local.environment}-${local.aws_region}-gpu-results-cdn"
  s3_bucket_id                   = dependency.s3_results.outputs.bucket_id
  s3_bucket_arn                  = dependency.s3_results.outputs.bucket_arn
  s3_bucket_regional_domain_name = dependency.s3_results.outputs.bucket_domain_name

  price_class = "PriceClass_100"

  # EU country whitelist for geo-restriction
  allowed_countries = ["FR", "DE", "GB", "ES", "IT", "NL", "BE", "AT", "CH", "PT"]

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-analysis"
    DataTier    = "delivery"
    ManagedBy   = "terragrunt"
  }
}
