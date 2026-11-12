include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud Inference Gateway — Catalog Unit (Reuses terraform/modules/gke-inference-gateway)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses `terraform/modules/gke-inference-gateway` with `gateway_class = "cilium"`,
# `enable_body_based_router = false`, and `cloud_armor_policy_id = null` to provision
# Kubernetes Gateway API + Inference Extension (`Gateway`, `InferencePool`, `InferenceObjective`)
# over OVH MKS Standard's native Cilium CNI.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-inference-gateway"
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
    provider "kubernetes" {
      host                   = "${dependency.mks.outputs.cluster_endpoint}"
      client_certificate     = base64decode("${dependency.mks.outputs.client_certificate}")
      client_key             = base64decode("${dependency.mks.outputs.client_key}")
      cluster_ca_certificate = base64decode("${dependency.mks.outputs.cluster_ca_certificate}")
    }
  PROVIDERS
}

inputs = {
  enabled                  = try(local.gpu_inference_config.inference_gateway_enabled, false)
  namespace                = try(local.gpu_inference_config.inference_namespace, "gpu-inference")
  gateway_class            = try(local.gpu_inference_config.inference_gateway_class, "cilium")
  inference_models         = try(local.gpu_inference_config.inference_models, [])
  enable_body_based_router = false
  cloud_armor_policy_id    = null

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-ml-platform"
  }
}
