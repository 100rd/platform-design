# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — YACE (CloudWatch exporter) — Catalog Unit — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# First workload in the ADR-0018 Pod Identity cutover (YACE -> observability stack
# -> ESO -> LB controller). Creates the Pod-Identity-trust IAM role + ABAC-scoped
# CloudWatch read policy + the PodIdentityAssociation for observability/yace.
#
# Deploy in each workload account/region whose EKS cluster runs YACE. After this
# unit is applied, drop the `eks.amazonaws.com/role-arn` IRSA annotation from the
# YACE ServiceAccount (apps/infra/observability/yace/values.yaml) so the SA does
# not carry both mechanisms (ADR-0018: precedence-both is unsupported).
#
# Prerequisite (assumed): the `eks-pod-identity-agent` EKS addon is installed on
# the target cluster.
#
# `cluster_name` MUST be supplied per-environment (no portable default): set it in
# the environment overlay's inputs or via a `dependency` on the eks unit.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/pod-identity-yace"
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

  # YACE deploys into the `observability` namespace with SA `yace` (matches the
  # YACE chart's serviceAccount.name). These are the module defaults; pinned here
  # for clarity and to drive the ABAC kubernetes-namespace condition.
  namespace       = "observability"
  service_account = "yace"

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    ADR         = "ADR-0018"
    Workload    = "yace"
  }
}
