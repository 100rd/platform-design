# -----------------------------------------------------------------------------
# _envcommon: VPC module — shared inputs and source pin
# -----------------------------------------------------------------------------
# Per-env CIDR allocation comes from each env's account.hcl / region.hcl.
# This file only fixes the contract (subnet layout, NAT posture, flow logs).
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/vpc"

  defaults = {
    # 3-AZ public/private/intra subnet split.
    enable_public_subnets  = true
    enable_private_subnets = true
    enable_intra_subnets   = false

    # NAT posture: per-env override (single-NAT in dev, per-AZ in prod).
    # Default to single-NAT to keep cost low; envs flip to per-AZ.
    enable_nat_gateway     = true
    single_nat_gateway     = true
    one_nat_gateway_per_az = false

    # Flow logs are non-negotiable — required by org-wide audit baseline.
    enable_flow_log                         = true
    flow_log_destination_type               = "cloud-watch-logs"
    flow_log_max_aggregation_interval       = 60
    flow_log_traffic_type                   = "ALL"
    flow_log_cloudwatch_log_group_retention = 90
  }
}

terraform {
  source = local.module_source
}

inputs = {
  enable_public_subnets                   = local.defaults.enable_public_subnets
  enable_private_subnets                  = local.defaults.enable_private_subnets
  enable_intra_subnets                    = local.defaults.enable_intra_subnets
  enable_nat_gateway                      = local.defaults.enable_nat_gateway
  single_nat_gateway                      = local.defaults.single_nat_gateway
  one_nat_gateway_per_az                  = local.defaults.one_nat_gateway_per_az
  enable_flow_log                         = local.defaults.enable_flow_log
  flow_log_destination_type               = local.defaults.flow_log_destination_type
  flow_log_max_aggregation_interval       = local.defaults.flow_log_max_aggregation_interval
  flow_log_traffic_type                   = local.defaults.flow_log_traffic_type
  flow_log_cloudwatch_log_group_retention = local.defaults.flow_log_cloudwatch_log_group_retention
}
