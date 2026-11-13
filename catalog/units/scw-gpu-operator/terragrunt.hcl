include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Kapsule GPU Operator — Catalog Unit (Reuses terraform/modules/gke-gpu-operator)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses the cloud-agnostic Helm GPU Operator module (`gke-gpu-operator`).
# Scaleway Kapsule GPU nodes ship NVIDIA drivers + container toolkit pre-installed in the
# Scaleway GPU OS image, so `driver_enabled = false` and `toolkit_enabled = false` by default
# while the operator manages the device plugin, GFD, NFD, and CDI.
#
# Dependencies: scw-kapsule-gpu
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-operator"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment          = local.project_vars.locals.environment
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

dependency "kapsule" {
  config_path = "../scw-kapsule-gpu"

  mock_outputs = {
    cluster_name           = "mock-scw-kapsule"
    cluster_endpoint       = "https://127.0.0.1:6443"
    cluster_ca_certificate = "bW9jay1jZXJ0LWRhdGE="
    kubeconfig_token       = "mock-token"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "scw_k8s_providers" {
  path      = "scw_k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.kapsule.outputs.cluster_endpoint}"
        token                  = "${dependency.kapsule.outputs.kubeconfig_token}"
        cluster_ca_certificate = base64decode("${dependency.kapsule.outputs.cluster_ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.kapsule.outputs.cluster_endpoint}"
      token                  = "${dependency.kapsule.outputs.kubeconfig_token}"
      cluster_ca_certificate = base64decode("${dependency.kapsule.outputs.cluster_ca_certificate}")
    }
  PROVIDERS
}

inputs = {
  enabled         = try(local.gpu_inference_config.gpu_operator_enabled, true)
  chart_version   = try(local.gpu_inference_config.gpu_operator_chart_version, "v24.9.2")
  driver_enabled  = try(local.gpu_inference_config.gpu_driver_managed_by_operator, false)
  toolkit_enabled = try(local.gpu_inference_config.gpu_toolkit_managed_by_operator, false)

  gpu_node_selector = {
    "node-role" = "gpu"
  }

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }
}
