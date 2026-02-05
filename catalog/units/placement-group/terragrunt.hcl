# ---------------------------------------------------------------------------------------------------------------------
# Placement Group — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates EC2 placement groups for controlling instance placement strategy.
# Used by blockchain HPC clusters to co-locate instances for low-latency networking.
#
# No dependencies — this is a foundational resource.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/placement-group"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment = local.account_vars.locals.environment
  aws_region  = local.region_vars.locals.aws_region
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  placement_groups = try(local.account_vars.locals.blockchain_config.placement_groups, {})

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
