# ---------------------------------------------------------------------------------------------------------------------
# Talos Cluster Bootstrap — Catalog Unit (WS-A — ml-infra) — ADR-0049
# ---------------------------------------------------------------------------------------------------------------------
# Bootstraps the self-operated Talos control plane (etcd + kubeconfig + snapshot schedule).
# Depends on talos-machineconfig for the secrets/client config.
#
# Apply-gated: enabled + bootstrap_control_plane both default OFF — etcd is never
# initialised in this mock repo.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/talos-cluster"
}

locals {
  project_vars = try(read_terragrunt_config(find_in_parent_folders("project.hcl")), { locals = {} })
  region_vars  = try(read_terragrunt_config(find_in_parent_folders("region.hcl")), { locals = {} })

  environment = try(local.project_vars.locals.environment, "staging")
  baremetal   = try(local.project_vars.locals.baremetal_config, {})
  dc          = try(local.region_vars.locals.uk_dc, "primary")
}

dependency "machineconfig" {
  config_path = "../talos-machineconfig"

  mock_outputs = {
    machine_secrets = {}
    client_configuration = {
      ca_certificate     = "bW9jay1jYQ=="
      client_certificate = "bW9jay1jZXJ0"
      client_key         = "bW9jay1rZXk="
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled                 = try(local.baremetal.talos_cluster_enabled, false)
  bootstrap_control_plane = try(local.baremetal.bootstrap_control_plane, false)

  cluster_name      = "uk-${local.dc}"
  control_plane_vip = try(local.baremetal.control_plane_vip, "10.10.0.10")

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
