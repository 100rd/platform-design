include "root" {
  path = find_in_parent_folders("root.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# GCP Cloud Armor (GPU inference frontend) — Catalog Unit (ADR-0042 D5)
# ---------------------------------------------------------------------------------------------------------------------
# WAF / DDoS / per-client rate-limit security policy for the GKE Inference Gateway LB.
# Gated OFF by default (gpu_analysis_config.cloud_armor_enabled); enabling is apply-gated.
#
# Requires project.hcl with: project_id, environment, gpu_analysis_config
# Requires region.hcl with: gcp_region
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gcp-cloud-armor"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  gcp_project_id      = local.project_vars.locals.project_id
  environment         = local.project_vars.locals.environment
  gcp_region          = local.region_vars.locals.gcp_region
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  enabled              = try(local.gpu_analysis_config.cloud_armor_enabled, false)
  project_id           = local.gcp_project_id
  security_policy_name = "${local.environment}-${local.gcp_region}-gpu-inference-armor"

  enable_adaptive_protection = try(local.gpu_analysis_config.cloud_armor_adaptive_protection, true)
  rate_limit_threshold       = try(local.gpu_analysis_config.cloud_armor_rate_limit, 600)
  waf_preconfigured_rules    = try(local.gpu_analysis_config.cloud_armor_waf_rules, ["sqli-v33-stable", "xss-v33-stable"])

  labels = {
    "platform.system"     = "ml-inference"
    "platform.component"  = "inference-armor"
    "platform.env"        = local.environment
    "platform.owner"      = "team-data-platform"
    "platform.managed-by" = "terragrunt"
  }
}
