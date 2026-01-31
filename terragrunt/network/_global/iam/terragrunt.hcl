# ---------------------------------------------------------------------------------------------------------------------
# Account-wide IAM Resources — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# Manages cross-account networking roles (e.g., TGW sharing, VPN management).
#
# TODO: Add IAM role definitions for cross-account access patterns.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/iam"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  environment  = local.account_vars.locals.environment
}

inputs = {
  account_name = local.account_name
  account_id   = local.account_id
  environment  = local.environment

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
