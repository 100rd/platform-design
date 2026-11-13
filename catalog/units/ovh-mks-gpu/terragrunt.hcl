include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "envcommon" {
  path           = find_in_parent_folders("_envcommon/ovh-mks-gpu.hcl")
  expose         = true
  merge_strategy = "deep"
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud MKS GPU Cluster & Node Pools — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an OVHcloud Managed Kubernetes Service (MKS) cluster (`STANDARD` plan with
# native Cilium eBPF CNI), system CPU pool, and GPU node pools (`l40s-90`, `h100-380`, `l4-90`)
# with scale-to-zero (`min_nodes = 0`).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  service_name         = local.project_vars.locals.service_name
  environment          = local.project_vars.locals.environment
  ovh_region           = local.region_vars.locals.ovh_region
  gpu_inference_config = local.project_vars.locals.gpu_inference_config
}

inputs = {
  service_name       = local.service_name
  cluster_name       = "${local.environment}-${lower(local.ovh_region)}-mks-gpu-inference"
  region             = local.ovh_region
  kubernetes_version = try(local.gpu_inference_config.kubernetes_version, include.envcommon.locals.defaults.kubernetes_version)
  cluster_plan       = try(local.gpu_inference_config.cluster_plan, include.envcommon.locals.defaults.cluster_plan)

  system_pool    = try(local.gpu_inference_config.system_pool, {})
  gpu_node_pools = local.gpu_inference_config.gpu_node_pools

  labels = {
    environment         = local.environment
    managed-by          = "terragrunt"
    cluster-role        = "gpu-inference"
    platform_system     = "ml-infrastructure"
    platform_component  = "mks-cluster"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "terragrunt"
  }
}
