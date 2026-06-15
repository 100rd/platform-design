# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-abac-iam — Catalog Unit (WS-E)
# ---------------------------------------------------------------------------------------------------------------------
# Least-privilege + ABAC IAM role (EKS Pod Identity) for ML workloads on the greenfield
# EKS GPU cluster (ADR-0018/0028/0048). Deploy in the GPU/ML workload account.
#
# Cross-unit wiring: the S3 artifact-store / KMS / Secrets ARNs come from the WS-B
# aws-ml-artifact-store unit via `dependency` blocks with mock_outputs for plan-time —
# wired here as empty defaults until that unit exists (this WS does not own it).
#
# APPLY-GATED: `enabled = false` by default — plan/validate creates no IAM. Enable only
# behind an explicit human apply (IAM is identity-critical).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/aws-ml-abac-iam"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

inputs = {
  # apply-gated OFF until a human enables it with a reviewed plan.
  enabled = false

  name            = "ml-platform-workload"
  platform_system = "ml-platform"

  # TODO: wire from the WS-B aws-ml-artifact-store unit via dependency.outputs when it
  # lands (bucket/kms/secret ARNs). Empty until then so plan-time stays inert.
  artifact_bucket_arns = []
  kms_key_arns         = []
  secret_arns          = []

  # TODO: set to the greenfield EKS GPU cluster name (ADR-0044) to create the Pod
  # Identity association; empty leaves the role assumable but unbound.
  eks_cluster_name          = ""
  service_account_namespace = "ml-platform"
  service_account_name      = "ml-platform-workload"

  tags = {
    "platform:env"        = local.environment
    "platform:managed-by" = "terragrunt"
  }
}
