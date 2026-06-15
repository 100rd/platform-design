# ---------------------------------------------------------------------------------------------------------------------
# GKE Inference Gateway — Catalog Unit (ADR-0042 D4)
# ---------------------------------------------------------------------------------------------------------------------
# Model-/KV-cache-aware serving front for vLLM (Gateway + InferencePool + InferenceObjective
# + Body-Based Router), with the Cloud Armor policy attached. Gated OFF by default
# (gpu_analysis_config.inference_gateway_enabled). Requires the GKE Inference Gateway
# CRDs on the cluster — apply-gated.
#
# Dependencies: gcp-gpu-gke (provider), gcp-cloud-armor (security policy)
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-inference-gateway"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment         = local.project_vars.locals.environment
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GKE cluster (provider auth) + Cloud Armor (security policy id)
# ---------------------------------------------------------------------------------------------------------------------

dependency "gke" {
  config_path = "../gcp-gpu-gke"

  mock_outputs = {
    name           = "mock-cluster"
    endpoint       = "10.0.0.1"
    ca_certificate = "bW9jay1jZXJ0LWRhdGE="
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "armor" {
  config_path = "../gcp-cloud-armor"

  mock_outputs = {
    security_policy_id = "projects/mock/global/securityPolicies/mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# PROVIDERS: GKE-authenticated kubernetes provider via google_client_config token.
# ---------------------------------------------------------------------------------------------------------------------

generate "gke_providers" {
  path      = "gke_providers_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDERS
    data "google_client_config" "this" {}

    provider "kubernetes" {
      host                   = "https://${dependency.gke.outputs.endpoint}"
      token                  = data.google_client_config.this.access_token
      cluster_ca_certificate = base64decode("${dependency.gke.outputs.ca_certificate}")
    }
  PROVIDERS
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  enabled       = try(local.gpu_analysis_config.inference_gateway_enabled, false)
  namespace     = try(local.gpu_analysis_config.inference_namespace, "gpu-inference")
  gateway_class = try(local.gpu_analysis_config.inference_gateway_class, "gke-l7-rilb")

  inference_models         = try(local.gpu_analysis_config.inference_models, [])
  enable_body_based_router = try(local.gpu_analysis_config.inference_body_based_router, true)

  # Attach Cloud Armor only when its unit is enabled (its output is null otherwise).
  cloud_armor_policy_id = dependency.armor.outputs.security_policy_id

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
