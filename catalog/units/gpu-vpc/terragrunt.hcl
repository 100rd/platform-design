# ---------------------------------------------------------------------------------------------------------------------
# GPU Analysis VPC Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Isolated VPC for the GPU video analysis EKS cluster.
# Uses a separate CIDR range (10.140+) to avoid overlap with platform and blockchain VPCs.
#
# Follows the same pattern as the blockchain VPC unit but with GPU-specific naming
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
  # GPU Analysis CIDR allocation map
  # Separate /16 blocks in the 10.140+ range to avoid overlap with platform
  # (10.x) and blockchain (10.100+) VPCs.
  # ---------------------------------------------------------------------------
  cidr_map = {
    dev-eu-west-1        = "10.140.0.0/16"
    dev-eu-west-2        = "10.141.0.0/16"
    dev-eu-west-3        = "10.142.0.0/16"
    dev-eu-central-1     = "10.143.0.0/16"
    staging-eu-west-1    = "10.150.0.0/16"
    staging-eu-west-2    = "10.151.0.0/16"
    staging-eu-west-3    = "10.152.0.0/16"
    staging-eu-central-1 = "10.153.0.0/16"
    prod-eu-west-1       = "10.160.0.0/16"
    prod-eu-west-2       = "10.161.0.0/16"
    prod-eu-west-3       = "10.162.0.0/16"
    prod-eu-central-1    = "10.163.0.0/16"
    dr-eu-west-1         = "10.170.0.0/16"
    dr-eu-west-2         = "10.171.0.0/16"
    dr-eu-west-3         = "10.172.0.0/16"
    dr-eu-central-1      = "10.173.0.0/16"
  }

  vpc_cidr     = local.cidr_map["${local.environment}-${local.aws_region}"]
  cluster_name = "${local.environment}-${local.aws_region}-gpu-analysis"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name = "${local.environment}-${local.aws_region}-gpu-analysis"
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
    ClusterRole = "gpu-analysis"
    ManagedBy   = "terragrunt"
  }
}
