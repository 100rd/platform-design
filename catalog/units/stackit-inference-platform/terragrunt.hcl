include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# STACKIT Inference Platform Services — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions STACKIT Object Storage (S3-compatible bucket for LLM weights & LoRA adapters)
# and STACKIT Observability / Argus (managed Prometheus/Thanos/Loki/Grafana linked to SKE).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/stackit-inference-platform"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  project_id           = local.project_vars.locals.project_id
  project_name         = local.project_vars.locals.project_name
  stackit_region       = local.region_vars.locals.stackit_region
  gpu_inference_config = try(local.project_vars.locals.gpu_inference_config, {})
}

inputs = {
  project_id              = local.project_id
  region                  = local.stackit_region
  models_bucket_name      = "${local.project_name}-${local.stackit_region}-llm-models"
  enable_observability    = try(local.gpu_inference_config.enable_observability, true)
  observability_plan_name = try(local.gpu_inference_config.observability_plan_name, "Observability-Monitoring-Medium-EU01")
}
