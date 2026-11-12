# -----------------------------------------------------------------------------
# _envcommon: STACKIT SKE GPU Cluster — shared inputs, dependencies, and source pin
# -----------------------------------------------------------------------------
# Included from STACKIT catalog/live units to keep SKE defaults, network wiring,
# and Observability (Argus) linkage DRY across environments.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/terraform/modules/stackit-ske-gpu"

  defaults = {
    kubernetes_version_min     = "1.31"
    control_plane_access_scope = "PUBLIC"
    auto_upgrade_enabled       = true
  }
}

terraform {
  source = local.module_source
}

dependency "vpc" {
  config_path = "../stackit-gpu-vpc"

  mock_outputs = {
    network_id = "00000000-0000-0000-0000-000000000001"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "platform" {
  config_path = "../stackit-inference-platform"

  mock_outputs = {
    observability_instance_id = "00000000-0000-0000-0000-000000000002"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  kubernetes_version_min     = local.defaults.kubernetes_version_min
  control_plane_access_scope = local.defaults.control_plane_access_scope
  auto_upgrade_enabled       = local.defaults.auto_upgrade_enabled

  network_id                = dependency.vpc.outputs.network_id
  observability_instance_id = dependency.platform.outputs.observability_instance_id
}
