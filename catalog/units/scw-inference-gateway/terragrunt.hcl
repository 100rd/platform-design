include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Inference Gateway — Catalog Unit (Reuses terraform/modules/gke-inference-gateway)
# ---------------------------------------------------------------------------------------------------------------------
# Reuses `terraform/modules/gke-inference-gateway` with `gateway_class = "cilium"`,
# `enable_body_based_router = false`, and `cloud_armor_policy_id = null` to provision pure
# Kubernetes Gateway API + Inference Extension (`Gateway`, `InferencePool`, `InferenceObjective`,
# `HTTPRoute`) for KV-cache-aware vLLM Multi-LoRA routing over Scaleway Kapsule Cilium CNI.
#
# Gated OFF by default (`gpu_inference_config.inference_gateway_enabled = false`) until
# Gateway API + Inference Extension CRDs are installed on the cluster.
#
# Dependencies: scw-kapsule-gpu
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-inference-gateway"
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
    provider "kubernetes" {
      host                   = "${dependency.kapsule.outputs.cluster_endpoint}"
      token                  = "${dependency.kapsule.outputs.kubeconfig_token}"
      cluster_ca_certificate = base64decode("${dependency.kapsule.outputs.cluster_ca_certificate}")
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
