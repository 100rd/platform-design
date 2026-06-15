# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-vpc — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# Greenfield GPU VPC (jumbo frames + EFA SG) for the AWS EKS GPU ML platform.
# ADR-0044 D5, ADR-0045 D1. Default-OFF (apply-gated): set gpu_platform_config.enabled
# = true in account.hcl to provision.
#
# Requires account.hcl (account_name, environment, optional gpu_platform_config) and
# region.hcl (aws_region).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-gpu-vpc"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  aws_region          = local.region_vars.locals.aws_region
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})

  cluster_name = "${local.environment}-${local.aws_region}-aws-eks-gpu"
}

inputs = {
  # Default-OFF — nothing is provisioned until explicitly enabled (apply gate).
  enabled = try(local.gpu_platform_config.enabled, false)

  name         = local.cluster_name
  cluster_name = local.cluster_name

  vpc_cidr        = try(local.gpu_platform_config.vpc_cidr, "10.80.0.0/16")
  azs             = try(local.gpu_platform_config.azs, [])
  private_subnets = try(local.gpu_platform_config.private_subnets, [])
  gpu_subnets     = try(local.gpu_platform_config.gpu_subnets, [])
  public_subnets  = try(local.gpu_platform_config.public_subnets, [])

  mtu                       = 9001
  single_az_gpu_subnet      = true
  enable_efa_security_group = true

  tags = {
    "platform:system"     = "ml-platform"
    "platform:component"  = "gpu-network"
    "platform:owner"      = "team-ml-platform"
    "platform:env"        = local.environment
    "platform:managed-by" = "terragrunt"
  }
}
