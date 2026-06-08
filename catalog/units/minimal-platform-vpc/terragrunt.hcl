# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform VPC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Isolated VPC for the minimal-platform EKS cluster in staging/eu-central-1.
# Uses CIDR 10.14.0.0/16 to avoid collision with the standard platform VPC (10.13.0.0/16).
#
# Key differences from the standard platform VPC unit:
#   - Cluster name: staging-eu-central-1-minimal-platform
#   - Single NAT gateway (Decision 1: saves ~$65/mo vs one-per-AZ)
#   - Dedicated CIDR 10.14.0.0/16
#   - VPC flow logs disabled (cost optimisation for test stack; PCI-DSS Req 10
#     retention requirement does not apply here — production stacks keep flow logs)
# ---------------------------------------------------------------------------------------------------------------------

# Include root.hcl to activate remote_state (S3 backend generation) and provider
# generation. Without this block, terragrunt ignores root.hcl entirely — no
# backend.tf is generated and state falls back to local storage, which is lost
# on any cache clean (rm -rf .terragrunt-cache / .terragrunt-stack).
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=6.6.0"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  # Fixed CIDR for the minimal-platform stack — dedicated allocation to avoid
  # collision with the standard platform VPC (10.13.0.0/16 for staging-eu-central-1).
  vpc_cidr     = "10.14.0.0/16"
  cluster_name = "${local.environment}-${local.aws_region}-minimal-platform"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name = local.cluster_name
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

  # Decision 1: single NAT gateway — cost optimisation for non-production minimal stack.
  # The standard platform stack uses one NAT gateway per AZ (account.hcl: single_nat_gateway = false).
  enable_nat_gateway = true
  single_nat_gateway = true

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ---------------------------------------------------------------------------
  # VPC Flow Logs — disabled for this test stack
  # ---------------------------------------------------------------------------
  # PCI-DSS Req 10.7 (12-month retention) does not apply to this non-production
  # test/validation stack. Disabling saves ~$5-10/mo in CloudWatch Logs ingestion
  # and storage. Production stacks (platform/, blockchain/) keep flow logs enabled.
  # See runbook: docs/runbooks/minimal-platform-bootstrap.md
  # ---------------------------------------------------------------------------
  enable_flow_log = false

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
