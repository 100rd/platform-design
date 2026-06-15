# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu — Greenfield EKS GPU ML cluster (ADR-0044 D1/D2/D6)
# ---------------------------------------------------------------------------------------------------------------------
# The control-plane half of the greenfield AWS EKS GPU ML platform. Mirrors the
# repo's eks-cluster module (upstream terraform-aws-modules/eks ~> 21.15) but:
#   * pins Kubernetes >= 1.33 so DRA is GA on EKS (ADR-0044 D2)
#   * carries the DynamicResourceAllocation intent as a conformance tag
#   * uses EKS Pod Identity (ADR-0018) authentication mode
#   * leaves GPU node provisioning to aws-eks-gpu-nodepools (Karpenter) and
#     aws-eks-gpu-managed-nodegroup (reserved EFA-DRA training) — no GPU node group here
#
# Default-OFF (var.enabled): nothing is provisioned until the apply gate is crossed.
# Bottlerocket GPU AMIs (ADR-0030) are selected on the node pools, not here.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  create = var.enabled

  base_tags = merge(
    {
      "platform:system"     = "ml-platform"
      "platform:component"  = "gpu-compute"
      "platform:managed-by" = "terragrunt"
    },
    var.tags,
    {
      # Conformance marker for the ADR-0044 D2 DRA floor.
      "platform:dra-feature-gate" = var.enable_dra_feature_gate ? "enabled" : "disabled"
    },
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  count = local.create ? 1 : 0

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # EKS Pod Identity + access-entry authentication (ADR-0018).
  authentication_mode = "API_AND_CONFIG_MAP"

  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Secrets envelope encryption (PCI-DSS Req 3.4) when a CMK is supplied.
  # Consistent object shape both branches (empty provider_key_arn disables).
  encryption_config = {
    provider_key_arn = var.kms_key_arn
    resources        = var.kms_key_arn != "" ? ["secrets"] : []
  }

  # Full control-plane logging (PCI-DSS Req 10.2).
  enabled_log_types = var.cluster_enabled_log_types

  # No GPU node groups here — GPU nodes come from aws-eks-gpu-nodepools (Karpenter)
  # and aws-eks-gpu-managed-nodegroup (reserved EFA-DRA training).
  eks_managed_node_groups = {}

  tags = local.base_tags
}
