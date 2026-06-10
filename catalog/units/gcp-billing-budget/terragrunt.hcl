# ---------------------------------------------------------------------------------------------------------------------
# GCP Billing Budget — Catalog Unit (WS-A — ml-infra)
# ---------------------------------------------------------------------------------------------------------------------
# Creates a billing budget scoped to the GPU project(s) with 80% / 100% / 120%
# threshold alerts delivered to a Pub/Sub topic that the Alertmanager webhook bridge
# subscribes to.
#
# No cluster dependency — this is a pure GCP billing/control-plane resource.
# Requires project.hcl with: project_id, environment, billing_account_id,
#                            gpu_analysis_config (optional monthly_amount override).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/gcp-billing-budget"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  gcp_project_id      = local.project_vars.locals.project_id
  environment         = local.project_vars.locals.environment
  billing_account_id  = local.project_vars.locals.billing_account_id
  gpu_analysis_config = try(local.project_vars.locals.gpu_analysis_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  billing_account_id = local.billing_account_id
  topic_project_id   = local.gcp_project_id
  gpu_project_ids    = [local.gcp_project_id]

  budget_display_name   = "ml-infra-gpu-${local.environment}"
  monthly_amount        = try(local.gpu_analysis_config.monthly_budget_amount, 10000)
  threshold_percentages = [0.8, 1.0, 1.2]

  pubsub_topic_name = "ml-infra-budget-alerts-${local.environment}"

  # ADR-0028 GCP-plane labels (underscore keys; system = ml-infra for WS-A).
  labels = {
    platform_env   = local.environment
    platform_owner = "team-data"
  }
}
