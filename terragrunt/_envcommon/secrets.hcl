# ---------------------------------------------------------------------------------------------------------------------
# Secrets Management Configuration
# ---------------------------------------------------------------------------------------------------------------------
# This _envcommon file defines the shared secrets management configuration used by all
# environments. It provisions AWS Secrets Manager secrets (and optionally SSM Parameter Store
# entries) using a custom Terraform module in the local modules directory.
#
# Secrets are namespaced by environment, region, and service to avoid collisions and
# simplify IAM policy scoping.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${dirname(find_in_parent_folders())}/../terraform/modules/secrets"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.env_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  environment   = local.environment
  region        = local.aws_region
  secret_prefix = "/${local.environment}/${local.aws_region}/platform"

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
