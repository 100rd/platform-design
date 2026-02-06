# ---------------------------------------------------------------------------------------------------------------------
# GCP GPU Node Pools — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys GPU-capable GKE node pools for video analysis workloads using the custom
# gcp-gke-gpu-nodepools module. Supports NVIDIA accelerators (T4, L4, A100, etc.)
# with automatic driver installation, spot instances, and Workload Identity.
#
# Node pool configurations are read from gpu_analysis_config.gpu_node_pools in
# project.hcl, allowing per-project customization of GPU types, counts, and scaling.
#
# Dependencies: gcp-gpu-gke
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region, zones
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gcp-gke-gpu-nodepools"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  gcp_project_id      = local.project_vars.locals.project_id
  environment         = local.project_vars.locals.environment
  gcp_region          = local.region_vars.locals.gcp_region
  gpu_analysis_config = local.project_vars.locals.gpu_analysis_config
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GCP GPU GKE Cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "gke" {
  config_path = "../gcp-gpu-gke"

  mock_outputs = {
    cluster_id = "projects/mock/locations/europe-west9/clusters/mock"
    name       = "mock-cluster"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  project_id   = local.gcp_project_id
  cluster_id   = dependency.gke.outputs.cluster_id
  cluster_name = dependency.gke.outputs.name
  zone         = local.region_vars.locals.zones[0]

  node_pool_configs = local.gpu_analysis_config.gpu_node_pools

  labels = {
    environment  = local.environment
    managed-by   = "terragrunt"
    cluster-role = "gpu-analysis"
  }
}
