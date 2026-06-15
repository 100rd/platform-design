# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Ingress WAF / Rate-limit — Catalog Unit (WS-A — ml-infra) — ADR-0053
# ---------------------------------------------------------------------------------------------------------------------
# On-prem WAF/rate-limit serving front (Cilium/Envoy Gateway) — the Cloud Armor mirror.
#
# Apply-gated: enabled defaults OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-ingress-waf"
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
  enabled         = try(local.baremetal.ingress_waf_enabled, false)
  gateway_backend = try(local.baremetal.ingress_gateway_backend, "cilium")

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
