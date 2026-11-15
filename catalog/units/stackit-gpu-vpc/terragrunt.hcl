include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# STACKIT GPU VPC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates a routed STACKIT virtual network for SKE worker nodes and GPU workloads.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/stackit-gpu-vpc"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  environment          = local.project_vars.locals.environment
  stackit_region       = local.region_vars.locals.stackit_region
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  project_id         = local.project_id
  network_name       = "${local.environment}-${local.stackit_region}-ske-gpu"
  region             = local.stackit_region
  routed             = true
  ipv4_prefix_length = try(local.gpu_inference_config.ipv4_prefix_length, 22)

  labels = {
    environment         = local.environment
    managed-by          = "terragrunt"
    cluster-role        = "gpu-inference"
    platform_system     = "ml-infrastructure"
    platform_component  = "gpu-vpc"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "terragrunt"
  }
}
