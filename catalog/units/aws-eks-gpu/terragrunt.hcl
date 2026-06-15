# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# Greenfield EKS GPU ML cluster (K8s >= 1.33 for DRA). ADR-0044 D1/D2/D6.
# Depends on aws-eks-gpu-vpc. Default-OFF (apply-gated).
#
# Requires account.hcl + region.hcl.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-gpu"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  aws_region          = local.region_vars.locals.aws_region
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})

  cluster_name = "${local.environment}-${local.aws_region}-aws-eks-gpu"
}

dependency "vpc" {
  config_path = "../aws-eks-gpu-vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000000", "subnet-11111111111111111"]
    gpu_subnet_ids     = ["subnet-33333333333333333"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled = try(local.gpu_platform_config.enabled, false)

  cluster_name    = local.cluster_name
  cluster_version = try(local.gpu_platform_config.cluster_version, "1.34")

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnet_ids

  cluster_endpoint_public_access = false
  kms_key_arn                    = try(local.gpu_platform_config.kms_key_arn, "")

  tags = {
    "platform:system"     = "ml-platform"
    "platform:component"  = "gpu-compute"
    "platform:owner"      = "team-ml-platform"
    "platform:env"        = local.environment
    "platform:managed-by" = "terragrunt"
  }
}
