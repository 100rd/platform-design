# -----------------------------------------------------------------------------
# _envcommon: Scaleway Kapsule GPU Cluster — shared inputs, dependencies, and source pin
# -----------------------------------------------------------------------------
# Included from Scaleway catalog/live units to keep cluster defaults and VPC
# dependency wiring DRY across environments (scw-dev, scw-staging, scw-prod).
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/terraform/modules/scw-kapsule-gpu"

  defaults = {
    cluster_type               = "kapsule-dedicated-4"
    kubernetes_version         = "1.32"
    public_ip_disabled         = true
    auto_upgrade_enabled       = true
    scale_down_delay_after_add = "5m"
    scale_down_unneeded_time   = "5m"
  }
}

terraform {
  source = local.module_source
}

dependency "vpc" {
  config_path = "../scw-gpu-vpc"

  mock_outputs = {
    vpc_id             = "fr-par/00000000-0000-0000-0000-000000000001"
    private_network_id = "fr-par/00000000-0000-0000-0000-000000000002"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  cluster_type               = local.defaults.cluster_type
  kubernetes_version         = local.defaults.kubernetes_version
  public_ip_disabled         = local.defaults.public_ip_disabled
  auto_upgrade_enabled       = local.defaults.auto_upgrade_enabled
  scale_down_delay_after_add = local.defaults.scale_down_delay_after_add
  scale_down_unneeded_time   = local.defaults.scale_down_unneeded_time

  private_network_id = dependency.vpc.outputs.private_network_id
}
