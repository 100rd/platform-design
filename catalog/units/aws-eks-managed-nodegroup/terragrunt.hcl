# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-managed-nodegroup — Catalog Unit (WS-A — ml-platform)
# ---------------------------------------------------------------------------------------------------------------------
# Reserved EFA-DRA training node group (ADR-0046 D2/D4, ADR-0045 D3). The narrow
# managed-node-group path for large reserved training. Depends on aws-eks-gpu +
# aws-eks-gpu-vpc (single GPU subnet). Default-OFF (apply-gated).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-eks-gpu-managed-nodegroup"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.account_vars.locals.environment
  gpu_platform_config = try(local.account_vars.locals.gpu_platform_config, {})

  # Reserved training is OFF unless BOTH the platform is enabled AND a training pool
  # is explicitly requested (it is the scarcest, most expensive capacity).
  training_enabled = try(local.gpu_platform_config.enabled, false) && try(local.gpu_platform_config.reserved_training_enabled, false)
}

dependency "eks" {
  config_path = "../aws-eks-gpu"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = ""
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "vpc" {
  config_path = "../aws-eks-gpu-vpc"

  mock_outputs = {
    gpu_subnet_ids    = ["subnet-33333333333333333"]
    efa_gpu_subnet_id = "subnet-33333333333333333"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled      = local.training_enabled
  cluster_name = dependency.eks.outputs.cluster_name
  subnet_ids   = dependency.vpc.outputs.gpu_subnet_ids

  instance_type                 = try(local.gpu_platform_config.training_instance_type, "p5.48xlarge")
  capacity_type                 = try(local.gpu_platform_config.training_capacity_type, "ON_DEMAND")
  capacity_block_reservation_id = try(local.gpu_platform_config.training_capacity_block_id, "")
  placement_group_name          = try(local.gpu_platform_config.training_placement_group, "")

  enable_efa = true
  efa_mode   = "dra"

  labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }

  tags = {
    "platform:owner" = "team-ml-platform"
    "platform:env"   = local.environment
  }
}
