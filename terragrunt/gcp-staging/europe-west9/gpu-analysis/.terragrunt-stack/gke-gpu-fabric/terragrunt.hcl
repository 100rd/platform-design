# ---------------------------------------------------------------------------------------------------------------------
# GKE GPU Fabric (GPUDirect-TCPX/TCPXO) — Catalog Unit (ADR-0042 D2)
# ---------------------------------------------------------------------------------------------------------------------
# Wires the GKENetworkParamSet + Network + NCCL plugin installer for H100/H100-Mega
# (a3-highgpu-8g / a3-megagpu-8g). Gated OFF by default (gpu_analysis_config.gpu_fabric_enabled).
# Consumes the data-plane VPCs from gcp-gpu-vpc.
#
# Dependencies: gcp-gpu-gke (provider), gcp-gpu-vpc (data-plane networks)
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gke-gpu-fabric"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  environment         = local.project_vars.locals.environment
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GKE cluster (provider auth) + GPU VPC (data-plane networks)
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

dependency "vpc" {
  config_path = "../gcp-gpu-vpc"

  mock_outputs = {
    data_plane_network_self_links = []
    data_plane_subnet_self_links  = []
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
# MODULE INPUTS — data_plane_networks derived from the gcp-gpu-vpc outputs.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  enabled = try(local.gpu_analysis_config.gpu_fabric_enabled, false)
  mode    = try(local.gpu_analysis_config.gpu_fabric_mode, "tcpx")

  data_plane_networks = [
    for i, nl in dependency.vpc.outputs.data_plane_network_self_links : {
      name       = basename(nl)
      network    = basename(nl)
      subnetwork = basename(dependency.vpc.outputs.data_plane_subnet_self_links[i])
    }
  ]

  platform_labels = {
    "platform.env"   = local.environment
    "platform.owner" = "team-data"
  }
}
