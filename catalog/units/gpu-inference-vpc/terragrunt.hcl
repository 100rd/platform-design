# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference VPC Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Dedicated VPC for the gpu-inference EKS cluster with BGP-native routing
# via AWS Transit Gateway Connect. Uses a separate Pod CIDR (100.64.0.0/10)
# announced via BGP to avoid ENI IP limits at scale (up to 5000 nodes).
#
# Prod-only deployment. CIDR range 10.180+ to avoid overlap with platform
# (10.0-53), blockchain (10.100-133), and gpu-analysis (10.140-173) VPCs.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-vpc"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  # ---------------------------------------------------------------------------
  # GPU Inference CIDR allocation map (prod only)
  # Separate /16 blocks in the 10.180+ range to avoid overlap with:
  #   platform:    10.0-53
  #   blockchain:  10.100-133
  #   gpu-analysis: 10.140-173
  # ---------------------------------------------------------------------------
  cidr_map = {
    prod-eu-west-1    = "10.180.0.0/16"
    prod-eu-west-2    = "10.181.0.0/16"
    prod-eu-west-3    = "10.182.0.0/16"
    prod-eu-central-1 = "10.183.0.0/16"
  }

  vpc_cidr     = local.cidr_map["${local.environment}-${local.aws_region}"]
  cluster_name = "${local.environment}-${local.aws_region}-gpu-inference"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name     = local.cluster_name
  vpc_cidr = local.vpc_cidr
  azs      = local.region_vars.locals.azs

  cluster_name = local.cluster_name

  # Private subnets: /20 blocks for GPU node groups (3 AZs)
  private_subnets = [for i, az in local.region_vars.locals.azs : cidrsubnet(local.vpc_cidr, 4, i)]

  # Intra subnets: /20 blocks for GPU node-to-node traffic (no NAT route)
  intra_subnets = [for i, az in local.region_vars.locals.azs : cidrsubnet(local.vpc_cidr, 4, i + 4)]

  # Pod CIDR announced via BGP (not part of VPC CIDR)
  pod_cidr = "100.64.0.0/10"

  # NAT Gateway — one per AZ in prod for HA
  single_nat_gateway = local.account_vars.locals.single_nat_gateway

  # Transit Gateway connectivity
  transit_gateway_id   = try(local.account_vars.locals.transit_gateway_id, "")
  tgw_route_table_id   = try(local.account_vars.locals.tgw_route_table_id, "")
  tgw_destination_cidr = "10.0.0.0/8"

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
