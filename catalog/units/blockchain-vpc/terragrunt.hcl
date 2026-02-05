# ---------------------------------------------------------------------------------------------------------------------
# Blockchain VPC Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Isolated VPC for the blockchain HPC EKS cluster.
# Uses a separate CIDR range (10.100+) to avoid overlap with the platform VPC.
#
# Follows the same pattern as the platform VPC unit but with blockchain-specific naming
# and CIDR allocation for network isolation.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.6.0"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  # ---------------------------------------------------------------------------
  # Blockchain CIDR allocation map
  # Separate /16 blocks in the 10.100+ range to avoid overlap with platform VPCs.
  # ---------------------------------------------------------------------------
  cidr_map = {
    dev-eu-west-1           = "10.100.0.0/16"
    dev-eu-west-2           = "10.101.0.0/16"
    dev-eu-west-3           = "10.102.0.0/16"
    dev-eu-central-1        = "10.103.0.0/16"
    staging-eu-west-1       = "10.110.0.0/16"
    staging-eu-west-2       = "10.111.0.0/16"
    staging-eu-west-3       = "10.112.0.0/16"
    staging-eu-central-1    = "10.113.0.0/16"
    prod-eu-west-1          = "10.120.0.0/16"
    prod-eu-west-2          = "10.121.0.0/16"
    prod-eu-west-3          = "10.122.0.0/16"
    prod-eu-central-1       = "10.123.0.0/16"
    dr-eu-west-1            = "10.130.0.0/16"
    dr-eu-west-2            = "10.131.0.0/16"
    dr-eu-west-3            = "10.132.0.0/16"
    dr-eu-central-1         = "10.133.0.0/16"
  }

  vpc_cidr     = local.cidr_map["${local.environment}-${local.aws_region}"]
  cluster_name = "${local.environment}-${local.aws_region}-blockchain"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name = "${local.environment}-${local.aws_region}-blockchain"
  cidr = local.vpc_cidr

  azs = local.region_vars.locals.azs

  # Subnet CIDR derivation — same scheme as platform VPC
  private_subnets  = [for i, az in local.region_vars.locals.azs : cidrsubnet(local.vpc_cidr, 4, i)]
  public_subnets   = [for i, az in local.region_vars.locals.azs : cidrsubnet(local.vpc_cidr, 4, i + 4)]
  database_subnets = [for i, az in local.region_vars.locals.azs : cidrsubnet(local.vpc_cidr, 4, i + 8)]

  # NAT Gateway configuration
  enable_nat_gateway = true
  single_nat_gateway = local.account_vars.locals.single_nat_gateway

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ---------------------------------------------------------------------------
  # Subnet tags required by AWS Load Balancer Controller and Karpenter
  # ---------------------------------------------------------------------------
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "karpenter.sh/discovery"                      = local.cluster_name
  }

  tags = {
    Environment = local.environment
    ClusterRole = "blockchain"
    ManagedBy   = "terragrunt"
  }
}
