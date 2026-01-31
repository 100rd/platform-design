# ---------------------------------------------------------------------------------------------------------------------
# VPC Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions a multi-AZ VPC with public, private, and database subnets
# using the terraform-aws-modules/vpc/aws registry module.
#
# CIDR allocation is deterministic per environment+region combination to avoid overlaps
# when peering VPCs across environments or regions.
#
# Hierarchy files (account.hcl, region.hcl) are read from the live tree via
# find_in_parent_folders when the unit executes in the context of a stack.
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
  # CIDR allocation map
  # Each environment+region pair gets a unique /16 block to prevent overlaps.
  #   dev:     10.0.x.0/16
  #   staging: 10.10.x.0/16
  #   prod:    10.20.x.0/16
  #   dr:      10.30.x.0/16
  #   network: 10.40.x.0/16
  #   reserved: 10.50-99 for future accounts
  # ---------------------------------------------------------------------------
  cidr_map = {
    dev-eu-west-1           = "10.0.0.0/16"
    dev-eu-west-2           = "10.1.0.0/16"
    dev-eu-west-3           = "10.2.0.0/16"
    dev-eu-central-1        = "10.3.0.0/16"
    staging-eu-west-1       = "10.10.0.0/16"
    staging-eu-west-2       = "10.11.0.0/16"
    staging-eu-west-3       = "10.12.0.0/16"
    staging-eu-central-1    = "10.13.0.0/16"
    prod-eu-west-1          = "10.20.0.0/16"
    prod-eu-west-2          = "10.21.0.0/16"
    prod-eu-west-3          = "10.22.0.0/16"
    prod-eu-central-1       = "10.23.0.0/16"
    dr-eu-west-1            = "10.30.0.0/16"
    dr-eu-west-2            = "10.31.0.0/16"
    dr-eu-west-3            = "10.32.0.0/16"
    dr-eu-central-1         = "10.33.0.0/16"
    network-eu-west-1       = "10.40.0.0/16"
    network-eu-west-2       = "10.41.0.0/16"
    network-eu-west-3       = "10.42.0.0/16"
    network-eu-central-1    = "10.43.0.0/16"
    management-eu-west-1    = "10.50.0.0/16"
    management-eu-west-2    = "10.51.0.0/16"
    management-eu-west-3    = "10.52.0.0/16"
    management-eu-central-1 = "10.53.0.0/16"
  }

  vpc_cidr     = local.cidr_map["${local.environment}-${local.aws_region}"]
  cluster_name = "${local.environment}-${local.aws_region}-platform"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name = "${local.environment}-${local.aws_region}-platform"
  cidr = local.vpc_cidr

  azs = local.region_vars.locals.azs

  # Subnet CIDR derivation using cidrsubnet on the VPC /16 block.
  # Each subnet gets a /20 (4 additional bits).
  #   private:  indices 0..N   (first AZ slots)
  #   public:   indices 4..N+4 (offset by 4)
  #   database: indices 8..N+8 (offset by 8)
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
    ManagedBy   = "terragrunt"
  }
}
