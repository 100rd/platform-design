# ---------------------------------------------------------------------------------------------------------------------
# TGW Route Tables — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Manages Transit Gateway route table associations and propagations.
# This is a logical unit that depends on TGW and RAM share being in place.
# Route tables are created by the transit-gateway module; this unit manages routes.
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

dependency "tgw" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock"
    route_table_ids    = {
      prod    = "tgw-rtb-mock-prod"
      nonprod = "tgw-rtb-mock-nonprod"
      shared  = "tgw-rtb-mock-shared"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name = "${local.account_name}-${local.aws_region}"

  # Blackhole routes to enforce environment isolation
  # Prod TGW route table blocks nonprod CIDRs and vice versa
  blackhole_cidrs = try(local.account_vars.locals.tgw_blackhole_cidrs, {})

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
