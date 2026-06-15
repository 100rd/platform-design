# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-artifact-store — Catalog Unit (WS-B — ml-pipeline, ADR-0048 D2)
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an S3 bucket + Pod Identity IAM role for MLflow artifact storage
# on the greenfield AWS EKS GPU ML cluster (ADR-0044).
#
# AWS mirror of catalog/units/ml-artifact-store (GCS / ADR-0037).
# ADR-0028: AWS-plane tags use colon separator (platform:system).
# ADR-0048 D2: ABAC condition gated on platform:system = ml-pipeline on both
#   the IAM role principal AND the S3 bucket resource.
# ADR-0018: EKS Pod Identity (not IRSA).
# Apply gate: create_resources defaults to false; the stack flips it to true
#   only after explicit human approval per the plan's apply-gated workflow.
#
# Required parent files: account.hcl (account_id, environment), region.hcl (aws_region).
# Optional: ml_pipeline_config map in account.hcl overrides all defaults.
# Dependency: ../aws-eks-gpu (outputs: cluster_name).
#   mock_outputs allow plan-only runs before the cluster is deployed.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-ml-artifact-store"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_id      = local.account_vars.locals.account_id
  environment     = local.account_vars.locals.environment
  aws_region      = local.region_vars.locals.aws_region
  ml_pipeline_cfg = try(local.account_vars.locals.ml_pipeline_config, {})
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: aws-eks-gpu cluster (EKS cluster name needed for Pod Identity trust).
# mock_outputs allow plan-only runs before the cluster exists.
# ---------------------------------------------------------------------------------------------------------------------

dependency "aws_eks_gpu" {
  config_path = "../aws-eks-gpu"

  mock_outputs = {
    cluster_name = "mock-aws-eks-gpu-cluster"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  bucket_name      = try(local.ml_pipeline_cfg.artifact_bucket_name, "mlflow-artifacts-${local.environment}-${local.account_id}")
  aws_region       = local.aws_region
  eks_cluster_name = dependency.aws_eks_gpu.outputs.cluster_name

  # KMS key ARN — sourced from environment config; leave empty for non-prod (AES256 fallback).
  kms_key_arn = try(local.ml_pipeline_cfg.artifact_kms_key_arn, "")

  versioning_enabled = try(local.ml_pipeline_cfg.artifact_bucket_versioning, true)

  # Lifecycle: prod uses full retention; non-prod transitions faster to cut cost.
  standard_ia_after_days = try(local.ml_pipeline_cfg.standard_ia_after_days, local.environment == "prod" ? 90 : 30)
  glacier_after_days     = try(local.ml_pipeline_cfg.glacier_after_days, local.environment == "prod" ? 365 : 90)
  expire_after_days      = try(local.ml_pipeline_cfg.expire_after_days, local.environment == "prod" ? 730 : 180)

  # Pod Identity role — one role per cluster/env (ADR-0018).
  mlflow_pod_identity_role_name     = try(local.ml_pipeline_cfg.pod_identity_role_name, "mlflow-artifact-store-${local.environment}")
  mlflow_kubernetes_namespace       = try(local.ml_pipeline_cfg.mlflow_k8s_namespace, "ml-pipeline")
  mlflow_kubernetes_service_account = try(local.ml_pipeline_cfg.mlflow_k8s_sa, "mlflow")

  # Apply gate — must be explicitly enabled via human-approved stack apply.
  create_resources = try(local.ml_pipeline_cfg.create_resources, false)

  # ADR-0028 AWS-plane tags (colon separator — AWS allows ':' in tag keys).
  tags = {
    "platform:system"     = "ml-pipeline"
    "platform:component"  = "model-registry"
    "platform:env"        = local.environment
    "platform:owner"      = try(local.ml_pipeline_cfg.owner, "team-ml")
    "platform:managed-by" = "terragrunt"
  }
}
