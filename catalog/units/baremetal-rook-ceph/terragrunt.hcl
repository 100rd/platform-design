# ---------------------------------------------------------------------------------------------------------------------
# Bare-metal Rook-Ceph Storage — Catalog Unit (WS-A — ml-infra) — ADR-0052
# ---------------------------------------------------------------------------------------------------------------------
# Rook-Ceph (block + FS + RGW S3). Sequenced AFTER talos-machineconfig (the rbd+ceph kernel
# modules MUST be declared there first) and talos-cluster. The ceph_kernel_modules input is
# wired from the machineconfig output so the module's validation enforces the ADR-0052 gate.
#
# Apply-gated: enabled defaults OFF.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/baremetal-rook-ceph"
}

locals {
  project_vars = try(read_terragrunt_config(find_in_parent_folders("project.hcl")), { locals = {} })
  region_vars  = try(read_terragrunt_config(find_in_parent_folders("region.hcl")), { locals = {} })

  environment = try(local.project_vars.locals.environment, "staging")
  baremetal   = try(local.project_vars.locals.baremetal_config, {})
  dc          = try(local.region_vars.locals.uk_dc, "primary")
}

# The rbd+ceph kernel-module contract (ADR-0052) is wired from talos-machineconfig.
dependency "machineconfig" {
  config_path = "../talos-machineconfig"

  mock_outputs = {
    ceph_kernel_modules = ["rbd", "ceph"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
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
  enabled = try(local.baremetal.rook_ceph_enabled, false)

  # ADR-0052 contract enforced in code: pass the modules the machineconfig declared.
  ceph_kernel_modules = dependency.machineconfig.outputs.ceph_kernel_modules

  enable_object_store = try(local.baremetal.ceph_object_store_enabled, true)
  block_pool_replicas = try(local.baremetal.ceph_replicas, 3)

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
