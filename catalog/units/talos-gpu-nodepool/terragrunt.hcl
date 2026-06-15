# ---------------------------------------------------------------------------------------------------------------------
# Talos GPU Node Pool — Catalog Unit (WS-A — ml-infra) — ADR-0049 / ADR-0054
# ---------------------------------------------------------------------------------------------------------------------
# A fixed-capacity GPU node pool (no autoscaler). Depends on talos-cluster for the
# kubeconfig used to apply the node-pool policy.
#
# Apply-gated: enabled defaults OFF; Cluster-API re-image path (manage_cluster_api) OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/talos-gpu-nodepool"
}

locals {
  project_vars = try(read_terragrunt_config(find_in_parent_folders("project.hcl")), { locals = {} })
  region_vars  = try(read_terragrunt_config(find_in_parent_folders("region.hcl")), { locals = {} })

  environment = try(local.project_vars.locals.environment, "staging")
  baremetal   = try(local.project_vars.locals.baremetal_config, {})
  dc          = try(local.region_vars.locals.uk_dc, "primary")
}

dependency "cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    kubeconfig       = "mock-kubeconfig"
    cluster_endpoint = "https://10.10.0.10:6443"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "k8s_provider" {
  path      = "k8s_provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "kubernetes" {
      config_path = "~/.kube/uk-${local.dc}.config"
    }
  PROVIDERS
}

inputs = {
  enabled            = try(local.baremetal.talos_gpu_nodepool_enabled, false)
  manage_cluster_api = try(local.baremetal.manage_cluster_api, false)

  cluster_name = "uk-${local.dc}"
  pool_name    = try(local.baremetal.gpu_pool_name, "h100-training")
  gpu_model    = try(local.baremetal.gpu_model, "H100")
  machines     = try(local.baremetal.gpu_machines, [])

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
