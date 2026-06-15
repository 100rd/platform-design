# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal GPU Fabric — Catalog Unit (WS-A — ml-infra) — ADR-0053
# ---------------------------------------------------------------------------------------------------------------------
# SR-IOV/RDMA day-0 primary + gated DRANET target, RoCEv2/InfiniBand.
#
# Apply-gated: enabled defaults OFF; DRANET target gated separately (enable_dranet OFF).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-gpu-fabric"
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
  enabled       = try(local.baremetal.gpu_fabric_enabled, false)
  fabric_mode   = try(local.baremetal.fabric_mode, "infiniband")
  enable_dranet = try(local.baremetal.fabric_dranet_enabled, false)

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
