# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity — EBS CSI Driver (controller) — Catalog Unit — ADR-0018
# ---------------------------------------------------------------------------------------------------------------------
# Storage-driver consumer in the ADR-0018 Pod Identity rollout. Creates the
# Pod-Identity-trust IAM role + ABAC-scoped EC2 volume-operations policy + the
# PodIdentityAssociation for kube-system/ebs-csi-controller-sa.
#
# After this unit is applied, drop the IRSA role from the EBS CSI controller SA. If
# the driver is an EKS managed addon, remove the addon's
# `service_account_role_arn` (no SA may carry both mechanisms; ADR-0018).
#
# Prerequisite (assumed): the `eks-pod-identity-agent` EKS addon is installed on
# the target cluster.
#
# `cluster_name` MUST be supplied per-environment (no portable default). Set
# `kms_key_arns` to the volume-encryption CMK(s) for least-privilege (defaults to
# "*").
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/pod-identity-ebs-csi"
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

  # The aws-ebs-csi-driver controller deploys into `kube-system` with SA
  # `ebs-csi-controller-sa`. These are the module defaults; pinned here for clarity
  # and to drive the ABAC kubernetes-namespace condition.
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"

  # Least-privilege KMS scoping (defaults to "*" when empty). Override per
  # environment with the real volume-encryption CMK ARN(s).

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    ADR         = "ADR-0018"
    Workload    = "ebs-csi-driver"
  }
}
