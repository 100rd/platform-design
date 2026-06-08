# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway — Network Account, eu-west-1
# ---------------------------------------------------------------------------------------------------------------------
# Hub for inter-VPC and inter-account connectivity. RAM-shares to all
# workload accounts so they can attach VPCs from their own units.
#
# Issue #170. Composes with #171 (inspection VPC) — that issue adds an
# 'inspection' route table.
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

  amazon_side_asn = 64512

  # Three segmented route tables enforce env isolation:
  #   prod    — only Prod VPCs attach here. Default propagation off.
  #   nonprod — Dev + Staging VPCs attach here.
  #   shared  — Shared services (ECR, Route53 PHZs) and the inspection VPC.
  # Cross-env reachability requires explicit per-CIDR routes from one RT
  # back to another; default is no leakage.
  route_tables = {
    prod    = {}
    nonprod = {}
    shared  = {}
  }

  # Blackhole CIDRs prevent accidental traffic flow across env boundaries
  # even if a route is ever added by mistake.
  blackhole_cidrs = {}

  # RAM share to every workload + shared-services account. Member
  # account IDs come from _org/account.hcl member_accounts; we list
  # them inline here for explicitness and easier auditability.
  ram_principals = [
    "111111111111", # dev
    "222222222222", # staging
    "333333333333", # prod
    "444444444444", # dr
    "777777777777", # security
    "888888888888", # log-archive
    "999999999999", # shared
  ]

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "transit-gateway"
  }
}
