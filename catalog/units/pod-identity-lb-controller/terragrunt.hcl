# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — AWS Load Balancer Controller — Catalog Unit — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Last workload in the ADR-0018 Pod Identity cutover (YACE -> observability stack
# -> ESO -> LB controller). Ingress-critical, so migrated last. Creates the
# Pod-Identity-trust IAM role + ABAC-scoped ELB/EC2 policy + the
# PodIdentityAssociation for kube-system/aws-load-balancer-controller.
#
# After this unit is applied, drop the IRSA `eks.amazonaws.com/role-arn` annotation
# from the LBC ServiceAccount (apps/infra/aws-lb-controller/values.yaml) so the SA
# does not carry both mechanisms (ADR-0018: precedence-both is unsupported).
#
# Prerequisite (assumed): the `eks-pod-identity-agent` EKS addon is installed on
# the target cluster.
#
# `cluster_name` MUST be supplied per-environment (no portable default): set it in
# the environment overlay's inputs or via a `dependency` on the eks unit.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/pod-identity-lb-controller"
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

  # The AWS Load Balancer Controller deploys into `kube-system` with SA
  # `aws-load-balancer-controller`. These are the module defaults; pinned here for
  # clarity and to drive the ABAC kubernetes-namespace condition.
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    ADR         = "ADR-0018"
    Workload    = "aws-load-balancer-controller"
  }
}
