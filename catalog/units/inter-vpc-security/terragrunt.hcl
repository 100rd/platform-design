# ---------------------------------------------------------------------------------------------------------------------
# Inter-VPC Access Security — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Wires ADR-0013's inter-VPC security model on the hub TGW: VPN route-table
# segmentation, the legacy-side routes (cross-estate join), and the prod NACL
# backstop. Pairs with the `remote-access-vpn` unit (the VPN host) and reads the
# TGW from the `transit-gateway` unit.
#
# SEQUENCING GATE (ADR-0013): enable_vpn_routing defaults to false. Flip it to
# true only AFTER the network VPC + attachment are applied AND the prod NACL
# backstop is in place. Route allow-lists are sourced from account.hcl
# (inter_vpc_security map) using representative/placeholder CIDRs + attachment
# IDs — no estate-specific values are hardcoded.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/inter-vpc-security"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  name = "${local.account_name}-${local.aws_region}"

  ivs   = try(local.account_vars.locals.inter_vpc_security, {})
  ravpn = try(local.account_vars.locals.remote_access_vpn, {})
}

dependency "tgw" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock"
    route_table_ids = {
      prod    = "tgw-rtb-mock-prod"
      nonprod = "tgw-rtb-mock-nonprod"
      shared  = "tgw-rtb-mock-shared"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "vpn" {
  config_path = "../remote-access-vpn"

  mock_outputs = {
    vpn_client_cidr           = "10.100.0.0/20"
    vpn_ops_subpool_cidr      = "10.100.0.0/24"
    vpn_standard_subpool_cidr = "10.100.1.0/24"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name               = local.name
  transit_gateway_id = dependency.tgw.outputs.transit_gateway_id

  # Sequencing gate — default OFF. Flip in account.hcl only after the network
  # VPC + attachment exist AND the prod NACL backstop is applied.
  enable_vpn_routing = try(local.ivs.enable_vpn_routing, false)
  network_vpc_id     = try(local.ivs.network_vpc_id, "")

  # Outbound allow-list (incl. legacy-side routes via the legacy admin-VPC
  # attachment). Placeholders unless overridden in account.hcl.
  vpn_forward_routes = try(local.ivs.vpn_forward_routes, {})

  # Return routes — ops sub-pool CIDR for prod-tier RTs (asymmetric return),
  # full pool for shared/dev-tier RTs. Placeholders unless overridden.
  vpn_return_routes = try(local.ivs.vpn_return_routes, {})

  # Prod NACL backstop (design-target) — independent gate so it can be applied
  # BEFORE routing is switched on.
  enable_prod_nacl_backstop = try(local.ivs.enable_prod_nacl_backstop, false)
  prod_subnet_nacl_ids      = try(local.ivs.prod_subnet_nacl_ids, [])

  vpn_ops_subpool_cidr      = try(dependency.vpn.outputs.vpn_ops_subpool_cidr, "10.100.0.0/24")
  vpn_standard_subpool_cidr = try(dependency.vpn.outputs.vpn_standard_subpool_cidr, "10.100.1.0/24")

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "inter-vpc-security"
    ADR         = "0013"
  }
}
