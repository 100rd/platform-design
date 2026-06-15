# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Cilium CNI + LB-IPAM + BGP — Catalog Unit (WS-A — ml-infra) — ADR-0051
# ---------------------------------------------------------------------------------------------------------------------
# Cilium CNI (kube-proxy-less) + LB-IPAM + BGP. CNI must exist before workloads, so this is
# sequenced right after talos-cluster.
#
# Apply-gated: enabled defaults OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-cilium-lb"
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
  enabled    = try(local.baremetal.cilium_lb_enabled, false)
  enable_bgp = try(local.baremetal.cilium_bgp_enabled, true)

  lb_ipam_cidrs = try(local.baremetal.lb_ipam_cidrs, ["10.20.0.0/24"])

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
