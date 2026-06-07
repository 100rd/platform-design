# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — Thanos (S3 object storage) — Catalog Unit — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Observability-stack step in the ADR-0018 Pod Identity cutover (YACE ->
# observability stack -> ESO -> LB controller). Creates the Pod-Identity-trust IAM
# role + ABAC-scoped S3 object-storage policy + the PodIdentityAssociation for
# monitoring/thanos.
#
# After this unit is applied, drop the IRSA `eks.amazonaws.com/role-arn` annotation
# from the Thanos ServiceAccount (the kube-prometheus-stack Thanos SA template) so
# the SA does not carry both mechanisms (ADR-0018: precedence-both is unsupported).
#
# `cluster_name` MUST be supplied per-environment (no portable default). Set
# `bucket_names` to the Thanos bucket(s) for least-privilege (defaults to "*").
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/pod-identity-thanos"
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

  # Thanos (kube-prometheus-stack) creates its SA `thanos` in the `monitoring`
  # namespace. These are the module defaults; pinned here for clarity and to drive
  # the ABAC kubernetes-namespace condition.
  namespace       = "monitoring"
  service_account = "thanos"

  # Least-privilege bucket scoping (defaults to "*" when empty). Override per
  # environment with the real Thanos bucket name(s), e.g.:
  #   bucket_names = ["platform-design-${local.environment}-thanos-metrics"]

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    ADR         = "ADR-0018"
    Workload    = "thanos"
  }
}
