include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# Scaleway Inference Platform Services — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions Scaleway Object Storage (for LLM weights & LoRA adapters), private Container
# Registry, and Scaleway Cockpit (managed Prometheus/Loki/Grafana observability).
#
# Requires project.hcl with: project_id, environment, gpu_inference_config
# Requires region.hcl with: scw_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/scw-inference-platform"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  project_name         = local.project_vars.locals.project_name
  environment          = local.project_vars.locals.environment
  scw_region           = local.region_vars.locals.scw_region
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  project_id                = local.project_id
  region                    = local.scw_region
  models_bucket_name        = "${local.project_name}-${local.scw_region}-llm-models"
  registry_namespace_name   = "${local.project_name}-${local.scw_region}-inference"
  enable_container_registry = try(local.gpu_inference_config.enable_container_registry, true)
  enable_cockpit            = try(local.gpu_inference_config.enable_cockpit, true)
  force_destroy_bucket      = local.environment != "prod"

  tags = {
    environment         = local.environment
    managed-by          = "terragrunt"
    platform_system     = "ml-infrastructure"
    platform_component  = "artifact-store"
    platform_env        = local.environment
    platform_owner      = "team-ml-platform"
    platform_managed_by = "terragrunt"
  }
}
