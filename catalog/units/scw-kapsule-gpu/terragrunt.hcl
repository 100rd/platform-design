include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = find_in_parent_folders("_envcommon/scw-kapsule-gpu.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Kapsule GPU Cluster & Node Pools — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a Scaleway Kapsule Dedicated Kubernetes cluster with Cilium CNI,
# system CPU pool, low-latency placement groups, and GPU node pools (L40S, H100, L4)
# configured for scale-to-zero and binpacking autoscaling.
#
# Dependencies: scw-gpu-vpc (inherited via _envcommon/scw-kapsule-gpu.hcl)
# Requires project.hcl with: project_id, environment, gpu_inference_config
# Requires region.hcl with: scw_region, scw_zone
# ---------------------------------------------------------------------------------------------------------------------

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  environment          = local.project_vars.locals.environment
  scw_region           = local.region_vars.locals.scw_region
  scw_zone             = local.region_vars.locals.scw_zone
  gpu_inference_config = local.project_vars.locals.gpu_inference_config
}

inputs = {
  project_id         = local.project_id
  cluster_name       = "${local.environment}-${local.scw_region}-scw-gpu-inference"
  cluster_type       = try(local.gpu_inference_config.cluster_type, include.envcommon.locals.defaults.cluster_type)
  kubernetes_version = try(local.gpu_inference_config.kubernetes_version, include.envcommon.locals.defaults.kubernetes_version)
  region             = local.scw_region
  zone               = local.scw_zone

  system_pool    = try(local.gpu_inference_config.system_pool, {})
  gpu_node_pools = local.gpu_inference_config.gpu_node_pools

  tags = {
    environment         = local.environment
    managed-by          = "terragrunt"
    cluster-role        = "gpu-inference"
    platform_system     = "ml-infrastructure"
    platform_component  = "kapsule-cluster"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "terragrunt"
  }
}
