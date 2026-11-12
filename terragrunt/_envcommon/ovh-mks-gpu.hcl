# -----------------------------------------------------------------------------
# _envcommon: OVHcloud MKS GPU Cluster — shared inputs, dependencies, and source pin
# -----------------------------------------------------------------------------
# Included from OVHcloud catalog/live units to keep MKS cluster defaults and
# vRack Private Network dependency wiring DRY across environments.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/terraform/modules/ovh-mks-gpu"

  defaults = {
    kubernetes_version = "1.31"
    cluster_plan       = "standard"
    update_policy      = "MINIMAL_DOWNTIME"
  }
}

terraform {
  source = local.module_source
}

dependency "vpc" {
  config_path = "../ovh-gpu-vpc"

  mock_outputs = {
    private_network_id = "00000000-0000-0000-0000-000000000001"
    subnet_id          = "00000000-0000-0000-0000-000000000002"
    gateway_ip         = "10.215.0.1"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  kubernetes_version    = local.defaults.kubernetes_version
  cluster_plan          = local.defaults.cluster_plan
  update_policy         = local.defaults.update_policy
  private_network_id    = dependency.vpc.outputs.private_network_id
  nodes_subnet_id       = dependency.vpc.outputs.subnet_id
  default_vrack_gateway = dependency.vpc.outputs.gateway_ip
}
