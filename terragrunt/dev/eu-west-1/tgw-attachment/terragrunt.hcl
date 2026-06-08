# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway VPC Attachment — Dev Account, eu-west-1
# ---------------------------------------------------------------------------------------------------------------------
# Attaches the dev VPC to the network-account TGW (shared via RAM by
# `terragrunt/network/eu-west-1/transit-gateway`).  Associates with the
# `nonprod` route table for env isolation.
#
# Issue #170 acceptance criterion: "at least one spoke attached and validated."
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/tgw-attachment"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# Pull the TGW ID + nonprod route-table ID from the network-account unit.
# Cross-account state-read works because the network account's state
# bucket (tfstate-network-eu-west-1) is read-only-shared with workload
# accounts via the bucket policy provisioned in #160.
dependency "tgw" {
  config_path = "../../../network/eu-west-1/transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock0123456789abcdef"
    route_table_ids = {
      prod    = "tgw-rtb-mock-prod"
      nonprod = "tgw-rtb-mock-nonprod"
      shared  = "tgw-rtb-mock-shared"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# Pull the local VPC ID + private subnet IDs from the platform stack's
# VPC unit. Lives at terragrunt/dev/eu-west-1/platform/vpc by convention.
dependency "vpc" {
  config_path = "../platform/vpc"

  mock_outputs = {
    vpc_id             = "vpc-mock0123456789abcdef"
    private_subnet_ids = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    private_route_table_ids = {
      "private-1" = "rtb-mock1"
      "private-2" = "rtb-mock2"
      "private-3" = "rtb-mock3"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name               = "${local.account_name}-${local.aws_region}"
  enabled            = local.account_vars.locals.enable_tgw_attachment
  transit_gateway_id = dependency.tgw.outputs.transit_gateway_id
  vpc_id             = dependency.vpc.outputs.vpc_id
  subnet_ids         = dependency.vpc.outputs.private_subnet_ids
  # Dev attaches to the nonprod RT.
  route_table_id      = dependency.tgw.outputs.route_table_ids["nonprod"]
  vpc_route_table_ids = dependency.vpc.outputs.private_route_table_ids
  # /8 covers the entire RFC-1918 internal range; spokes still need
  # specific routes to reach each other (set in the TGW route tables).
  tgw_destination_cidr = "10.0.0.0/8"

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "tgw-attachment"
  }
}
