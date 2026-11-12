include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# OVHcloud Inference Platform Services — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions OVHcloud S3 Object Storage (for LLM weights & LoRA adapters) and Managed
# Private Registry (Harbor) in GRA.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/ovh-inference-platform"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  service_name         = local.project_vars.locals.service_name
  project_name         = local.project_vars.locals.project_name
  ovh_s3_region        = local.region_vars.locals.ovh_s3_region
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  service_name              = local.service_name
  s3_region                 = local.ovh_s3_region
  models_bucket_name        = "${local.project_name}-${lower(local.ovh_s3_region)}-llm-models"
  registry_name             = "${local.project_name}-${lower(local.ovh_s3_region)}-inference"
  enable_container_registry = try(local.gpu_inference_config.enable_container_registry, true)
  registry_plan_id          = try(local.gpu_inference_config.registry_plan_id, "SMALL")
}
