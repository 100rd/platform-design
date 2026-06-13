# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU DRANET (RoCE/RDMA) — Catalog Unit (ADR-0042 D3)
# ---------------------------------------------------------------------------------------------------------------------
# Ships the DRA netdev DeviceClass + ResourceClaimTemplate for GPUDirect-RDMA/RoCE on
# H200/B200 (a3-ultragpu-8g, a4-highgpu-8g). Gated OFF by default
# (gpu_analysis_config.dranet_enabled). Requires GKE managed DRANET on the cluster
# (>= 1.35.2-gke.1842000) and a RoCE VPC — both apply-gated prerequisites.
#
# Dependencies: gcp-gpu-gke
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-dranet"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment         = local.project_vars.locals.environment
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GCP GPU GKE Cluster (for the kubernetes provider auth)
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
  enabled   = try(local.gpu_analysis_config.dranet_enabled, false)
  namespace = try(local.gpu_analysis_config.inference_namespace, "gpu-inference")

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
