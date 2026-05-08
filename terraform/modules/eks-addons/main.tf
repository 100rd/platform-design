# ---------------------------------------------------------------------------------------------------------------------
# EKS Addons Module
# ---------------------------------------------------------------------------------------------------------------------
# Deploys EKS managed addons that require running nodes (e.g. CoreDNS).
# Must be applied AFTER eks-nodes so the addon pods have somewhere to schedule.
#
# Deploy order:
#   vpc -> kms -> eks-cluster -> cilium -> eks-nodes -> eks-addons (this module)
#
# Why a separate module:
#   aws_eks_addon waits for the addon to reach ACTIVE status. ACTIVE requires
#   the addon pods to be Running. CoreDNS is a Deployment — it needs Ready nodes.
#   Placing CoreDNS here (post-nodes) prevents the apply from hanging indefinitely
#   in the eks-cluster unit where no nodes exist yet.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = each.value.resolve_conflicts
  resolve_conflicts_on_update = each.value.resolve_conflicts
  service_account_role_arn    = each.value.service_account_role_arn
  preserve                    = each.value.preserve

  tags = merge(var.tags, each.value.tags)
}
