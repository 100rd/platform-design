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
#
# Tier-1 compute (doc-verified 2026-06-07):
#   This module is generic — it deploys any managed addon supplied via var.addons.
#   Callers wire the "eks-node-monitoring-agent" addon (a DaemonSet that surfaces
#   node health conditions) here so that Karpenter's NodeRepair / Node Auto-Repair
#   feature gate has a health signal to act on. See the karpenter module for the
#   matching settings.featureGates.nodeRepair wiring and the 20% NodePool cap.
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
