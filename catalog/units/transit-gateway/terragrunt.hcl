# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Creates the central Transit Gateway for inter-VPC and inter-account connectivity.
# Deployed only in the network account.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/transit-gateway"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

inputs = {
  name = "${local.account_name}-${local.aws_region}"

  route_tables = {
    prod    = {}
    nonprod = {}
    shared  = {}
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
