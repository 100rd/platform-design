# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — External Secrets Operator (ESO) — Catalog Unit — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Third workload in the ADR-0018 Pod Identity cutover (YACE -> observability stack
# -> ESO -> LB controller). Creates the Pod-Identity-trust IAM role + ABAC-scoped
# SecretsManager/KMS/ECR policy + the PodIdentityAssociation for the ESO controller
# SA (external-secrets/external-secrets).
#
# ESO uses the identity bound to its OWN controller SA via this association — NOT
# `serviceAccountRef` (ADR-0018 sub-decision). Prerequisite: ESO upgraded to v2.6.0
# (CRDs move to v1) before migrating ESO onto Pod Identity.
#
# After this unit is applied, ensure the ESO controller SA does not carry
# `eks.amazonaws.com/role-arn` (no SA may carry both mechanisms; ADR-0018).
#
# `cluster_name` MUST be supplied per-environment (no portable default): set it in
# the environment overlay's inputs or via a `dependency` on the eks unit.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/pod-identity-eso"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
}

inputs = {
  project = "platform-design"

  # Placeholder — override per environment with the real EKS cluster name (or wire
  # a `dependency "eks"` and pass `dependency.eks.outputs.cluster_name`).
  cluster_name = "platform-${local.environment}"

  # ESO controller deploys into the `external-secrets` namespace with SA
  # `external-secrets`. These are the module defaults; pinned here for clarity and
  # to drive the ABAC kubernetes-namespace condition.
  namespace       = "external-secrets"
  service_account = "external-secrets"

  # Optional least-privilege scoping (defaults to "*" when empty):
  #   secret_arn_patterns = ["arn:aws:secretsmanager:*:*:secret:/platform/*"]
  #   kms_key_arns        = ["arn:aws:kms:*:*:key/<secrets-cmk-id>"]

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    ADR         = "ADR-0018"
    Workload    = "external-secrets"
  }
}
