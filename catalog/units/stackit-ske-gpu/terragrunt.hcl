include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = find_in_parent_folders("_envcommon/stackit-ske-gpu.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# STACKIT SKE GPU Cluster & Node Pools — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a Gardener-based STACKIT SKE cluster with native Cilium CNI, Observability
# (Argus) extension, system CPU pool, and GPU node pools (L40S, H100, L4) with scale-to-zero.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  environment          = local.project_vars.locals.environment
  stackit_region       = local.region_vars.locals.stackit_region
  availability_zones   = local.region_vars.locals.availability_zones
  gpu_inference_config = local.project_vars.locals.gpu_inference_config
}

inputs = {
  project_id             = local.project_id
  cluster_name           = try(local.gpu_inference_config.cluster_name, "ske-gpu-inf")
  region                 = local.stackit_region
  availability_zones     = local.availability_zones
  kubernetes_version_min = try(local.gpu_inference_config.kubernetes_version_min, include.envcommon.locals.defaults.kubernetes_version_min)

  system_pool    = try(local.gpu_inference_config.system_pool, {})
  gpu_node_pools = local.gpu_inference_config.gpu_node_pools

  labels = {
    environment         = local.environment
    managed-by          = "terragrunt"
    cluster-role        = "gpu-inference"
    platform_system     = "ml-infrastructure"
    platform_component  = "ske-cluster"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "terragrunt"
  }
}
