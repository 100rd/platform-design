include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud MKS GPU Operator — Catalog Unit (Reuses terraform/modules/gke-gpu-operator)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses `terraform/modules/gke-gpu-operator` with `driver_enabled = true` and `toolkit_enabled = true`
# so the NVIDIA GPU Operator automatically installs CUDA drivers and container toolkit on OVH MKS GPU nodes.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-operator"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment          = local.project_vars.locals.environment
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

dependency "mks" {
  config_path = "../ovh-mks-gpu"

  mock_outputs = {
    cluster_name           = "mock-ovh-mks"
    cluster_endpoint       = "https://127.0.0.1:6443"
    cluster_ca_certificate = "bW9jay1jZXJ0LWRhdGE="
    client_certificate     = "bW9jay1jZXJ0LWRhdGE="
    client_key             = "bW9jay1rZXktZGF0YQ=="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "ovh_k8s_providers" {
  path      = "ovh_k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.mks.outputs.cluster_endpoint}"
        client_certificate     = base64decode("${dependency.mks.outputs.client_certificate}")
        client_key             = base64decode("${dependency.mks.outputs.client_key}")
        cluster_ca_certificate = base64decode("${dependency.mks.outputs.cluster_ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.mks.outputs.cluster_endpoint}"
      client_certificate     = base64decode("${dependency.mks.outputs.client_certificate}")
      client_key             = base64decode("${dependency.mks.outputs.client_key}")
      cluster_ca_certificate = base64decode("${dependency.mks.outputs.cluster_ca_certificate}")
    }
  PROVIDERS
}

inputs = {
  enabled         = try(local.gpu_inference_config.gpu_operator_enabled, true)
  chart_version   = try(local.gpu_inference_config.gpu_operator_chart_version, "v24.9.2")
  driver_enabled  = try(local.gpu_inference_config.gpu_driver_managed_by_operator, true)
  toolkit_enabled = try(local.gpu_inference_config.gpu_toolkit_managed_by_operator, true)

  gpu_node_selector = {
    "node-role" = "gpu"
  }

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }
}
