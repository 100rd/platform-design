# ---------------------------------------------------------------------------------------------------------------------
# TGW Peering — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Creates cross-region Transit Gateway peering attachments and adds routes for
# remote CIDRs in each local TGW route table.
# Gated by enable_tgw_peering in account.hcl.
# Depends on transit-gateway being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/tgw-peering"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  tgw_peers = try(local.account_vars.locals.tgw_peers, {})
}

dependency "transit_gateway" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id       = "tgw-mock"
    transit_gateway_owner_id = "555555555555"
    route_table_ids          = { prod = "tgw-rtb-mock-1", nonprod = "tgw-rtb-mock-2", shared = "tgw-rtb-mock-3" }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# Generate provider configuration for the peer region
generate "peer_provider" {
  path      = "peer-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias  = "peer"
      region = var.peer_region
    }
  EOF
}

inputs = {
  enabled         = try(local.account_vars.locals.enable_tgw_peering, false)
  name            = "${local.account_name}-${local.aws_region}"
  local_tgw_id    = dependency.transit_gateway.outputs.transit_gateway_id
  peer_tgw_id     = try(local.tgw_peers[local.aws_region] != null ? "" : "", "")
  peer_region     = "" # Populated per-region in live tree overrides
  peer_account_id = dependency.transit_gateway.outputs.transit_gateway_owner_id

  local_route_table_ids = dependency.transit_gateway.outputs.route_table_ids

  peer_cidrs = [] # Populated per-region in live tree overrides

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
