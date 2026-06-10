# ---------------------------------------------------------------------------------------------------------------------
# MLflow Artifact Store — Catalog Unit (WS-B — ml-pipeline)
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a GCS bucket + Workload Identity GSA for MLflow artifact storage.
# Designed for use in the ML-pipeline GCP project alongside the gcp-gpu-gke cluster.
#
# Dependencies: gcp-gpu-gke  (outputs: project_id, name)
# Requires project.hcl with: project_id, environment
# Optional project.hcl key: ml_pipeline_config (see inputs block for defaults)
#
# ADR-0028: GCP-plane labels use underscore keys (platform_system, not platform:system).
# ADR-0037: system = ml-pipeline, component = model-registry.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/ml-artifact-store"
}

locals {
  project_vars = read_terragrunt_config(find_in_parent_folders("project.hcl"))

  gcp_project_id     = local.project_vars.locals.project_id
  environment        = local.project_vars.locals.environment
  ml_pipeline_config = try(local.project_vars.locals.ml_pipeline_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: GCP GPU GKE cluster
# The bucket name is derived from the project id so there is no hard data-dependency,
# but we take a soft dep so the cluster is present before IAM bindings are created.
# ---------------------------------------------------------------------------------------------------------------------

dependency "gke" {
  config_path = "../gcp-gpu-gke"

  mock_outputs = {
    name       = "mock-cluster"
    project_id = "mock-project-123"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  project_id  = local.gcp_project_id
  bucket_name = try(local.ml_pipeline_config.artifact_bucket_name, "mlflow-artifacts-${local.environment}-${local.gcp_project_id}")
  location    = try(local.ml_pipeline_config.artifact_bucket_location, "US")

  storage_class = try(
    local.ml_pipeline_config.artifact_bucket_storage_class,
    local.environment == "prod" ? "MULTI_REGIONAL" : "STANDARD",
  )

  versioning_enabled = try(local.ml_pipeline_config.artifact_bucket_versioning, true)

  # Lifecycle: prod uses full retention; non-prod transitions faster to cut cost.
  nearline_after_days = try(local.ml_pipeline_config.nearline_after_days, local.environment == "prod" ? 90 : 30)
  coldline_after_days = try(local.ml_pipeline_config.coldline_after_days, local.environment == "prod" ? 365 : 90)
  deletion_after_days = try(local.ml_pipeline_config.deletion_after_days, local.environment == "prod" ? 730 : 180)

  # Workload Identity — GKE KSA mlflow/ml-pipeline impersonates the GSA.
  workload_identity_sa_name  = try(local.ml_pipeline_config.wi_sa_name, "mlflow-artifact-store")
  kubernetes_namespace       = try(local.ml_pipeline_config.mlflow_k8s_namespace, "ml-pipeline")
  kubernetes_service_account = try(local.ml_pipeline_config.mlflow_k8s_sa, "mlflow")

  # ADR-0028 GCP-plane labels (underscore keys; system = ml-pipeline for WS-B).
  labels = {
    platform_system     = "ml-pipeline"
    platform_component  = "model-registry"
    platform_env        = local.environment
    platform_owner      = try(local.ml_pipeline_config.owner, "team-ml")
    platform_managed_by = "terragrunt"
  }
}
