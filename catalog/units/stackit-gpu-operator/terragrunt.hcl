include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# STACKIT SKE GPU Operator — Catalog Unit (Reuses terraform/modules/gke-gpu-operator)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses `terraform/modules/gke-gpu-operator`. Per STACKIT SKE documentation, SKE Ubuntu
# GPU node images do not pre-install NVIDIA drivers, so `driver_enabled = true` and
# `toolkit_enabled = true` by default so the NVIDIA GPU Operator manages the full driver stack.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-operator"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment          = local.project_vars.locals.environment
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

dependency "ske" {
  config_path = "../stackit-ske-gpu"

  mock_outputs = {
    cluster_name           = "ske-gpu-inf"
    cluster_endpoint       = "https://127.0.0.1:6443"
    cluster_ca_certificate = "bW9jay1jZXJ0LWRhdGE="
    client_certificate     = "bW9jay1jZXJ0LWRhdGE="
    client_key             = "bW9jay1rZXktZGF0YQ=="
    kubeconfig_token       = "mock-token"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "stackit_k8s_providers" {
  path      = "stackit_k8s_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    provider "helm" {
      kubernetes {
        host                   = "${dependency.ske.outputs.cluster_endpoint}"
        token                  = "${dependency.ske.outputs.kubeconfig_token}"
        client_certificate     = base64decode("${dependency.ske.outputs.client_certificate}")
        client_key             = base64decode("${dependency.ske.outputs.client_key}")
        cluster_ca_certificate = base64decode("${dependency.ske.outputs.cluster_ca_certificate}")
      }
    }

    provider "kubernetes" {
      host                   = "${dependency.ske.outputs.cluster_endpoint}"
      token                  = "${dependency.ske.outputs.kubeconfig_token}"
      client_certificate     = base64decode("${dependency.ske.outputs.client_certificate}")
      client_key             = base64decode("${dependency.ske.outputs.client_key}")
      cluster_ca_certificate = base64decode("${dependency.ske.outputs.cluster_ca_certificate}")
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
