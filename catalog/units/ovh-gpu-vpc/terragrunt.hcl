include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud GPU Private Network (vRack) & Gateway — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an isolated vRack Private Network, subnet, and OVHcloud Public Cloud Gateway (SNAT)
# for private MKS GPU worker nodes in GRA11.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/ovh-gpu-vpc"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  service_name         = local.project_vars.locals.service_name
  environment          = local.project_vars.locals.environment
  ovh_region           = local.region_vars.locals.ovh_region
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  service_name   = local.service_name
  network_name   = "${local.environment}-${lower(local.ovh_region)}-mks-gpu-pn"
  region         = local.ovh_region
  vlan_id        = try(local.gpu_inference_config.vlan_id, 140)
  subnet_cidr    = try(local.gpu_inference_config.subnet_cidr, "10.215.0.0/16")
  enable_gateway = try(local.gpu_inference_config.enable_gateway, true)
  gateway_model  = try(local.gpu_inference_config.gateway_model, "s")
}
