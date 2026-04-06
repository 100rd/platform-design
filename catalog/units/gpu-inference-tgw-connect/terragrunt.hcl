# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference TGW Connect BGP Peering — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates TGW Connect peers for BGP sessions between the gpu-inference cluster
# and Transit Gateway. One peer per AZ for HA. Propagates Pod CIDR
# (100.64.0.0/10) to shared route table for cross-cluster communication.
#
# Depends on gpu-inference-vpc (provides tgw_connect_attachment_id).
# Consumed by Cilium BGP peering policy (Issue #70).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/gpu-inference-tgw-connect"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment          = local.account_vars.locals.environment
  aws_region           = local.region_vars.locals.aws_region
  gpu_inference_config = try(local.account_vars.locals.gpu_inference_config, {})
  cluster_name         = "${local.environment}-${local.aws_region}-gpu-inference"
}

dependency "vpc" {
  config_path = "../gpu-inference-vpc"

  mock_outputs = {
    tgw_connect_attachment_id = "tgw-attach-mock"
    pod_cidr                  = "100.64.0.0/10"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name                      = local.cluster_name
  tgw_connect_attachment_id = dependency.vpc.outputs.tgw_connect_attachment_id
  tgw_route_table_id        = try(local.account_vars.locals.tgw_route_table_id, "")
  shared_route_table_id     = try(local.account_vars.locals.tgw_shared_route_table_id, "")
  pod_cidr                  = dependency.vpc.outputs.pod_cidr
  enable_static_fallback    = true

  # BGP peers — empty by default, populated after TGW Connect deployment
  bgp_peers = try(local.gpu_inference_config.tgw_bgp_peers, {})

  tags = {
    Environment = local.environment
    ClusterRole = "gpu-inference"
    ManagedBy   = "terragrunt"
  }
}
