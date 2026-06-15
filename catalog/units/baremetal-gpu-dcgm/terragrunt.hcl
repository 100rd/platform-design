# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU DCGM — Catalog Unit (WS-A — ml-infra) — ADR-0049 / ADR-0050
# ---------------------------------------------------------------------------------------------------------------------
# DCGM exporter + GPU-health auto-taint on the Talos GPU nodes.
#
# Apply-gated: enabled defaults OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-gpu-dcgm"
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

generate "k8s_providers" {
  path      = "k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        config_path = "~/.kube/uk-${local.dc}.config"
      }
    }

    provider "kubernetes" {
      config_path = "~/.kube/uk-${local.dc}.config"
    }
  PROVIDERS
}

inputs = {
  enabled           = try(local.baremetal.gpu_dcgm_enabled, false)
  enable_auto_taint = try(local.baremetal.gpu_auto_taint_enabled, true)

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
