# ---------------------------------------------------------------------------------------------------------------------
# VPN Connection — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Creates Site-to-Site VPN connections for 3rd-party partners and on-premises.
# Terminates on the Transit Gateway.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/vpn-connection"
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
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name               = "${local.account_name}-${local.aws_region}"
  transit_gateway_id = dependency.tgw.outputs.transit_gateway_id
  vpn_connections    = try(local.account_vars.locals.vpn_connections, {})

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
