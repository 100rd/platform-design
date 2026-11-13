include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway GPU VPC — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates a Scaleway VPC, regional Private Network (with IPAM subnet), and Public Gateway
# (NAT masquerading) for private Kapsule GPU inference nodes.
#
# Requires project.hcl with: project_id, environment, gpu_inference_config
# Requires region.hcl with: scw_region, scw_zone
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/scw-gpu-vpc"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  environment          = local.project_vars.locals.environment
  scw_region           = local.region_vars.locals.scw_region
  scw_zone             = local.region_vars.locals.scw_zone
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  project_id            = local.project_id
  network_name          = "${local.environment}-${local.scw_region}-scw-gpu-inference"
  region                = local.scw_region
  zone                  = local.scw_zone
  subnet_cidr           = try(local.gpu_inference_config.subnet_cidr, "10.210.0.0/16")
  enable_public_gateway = try(local.gpu_inference_config.enable_public_gateway, true)
  public_gateway_type   = try(local.gpu_inference_config.public_gateway_type, "VPC-GW-S")
  bastion_enabled       = try(local.gpu_inference_config.bastion_enabled, false)

  tags = {
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
