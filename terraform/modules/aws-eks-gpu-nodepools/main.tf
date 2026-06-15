# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-nodepools — Karpenter GPU pools wrapper (ADR-0046 D1/D3, ADR-0045 D1/D2)
# ---------------------------------------------------------------------------------------------------------------------
# A thin GPU-defaults wrapper over the existing terraform/modules/karpenter-nodepools.
# It reuses that module's spot/scale-to-zero/consolidation/placement-group/single-AZ
# behaviour (ADR-0046 says D1/D3 are configuration, not new module code) and adds:
#   * GPU taints (nvidia.com/gpu) + GPU pool labels
#   * EFA wiring: enable_efa pools pin a cluster placement group + single AZ and run
#     the EFA *device plugin* (Karpenter cannot run the EFA DRA driver, ADR-0045 D2).
#   * spot_percentage = 0 for EFA training pools (no spot mid-NCCL, ADR-0046 D3).
#
# Default-OFF (var.enabled). NodePools/EC2NodeClasses are kubernetes_manifest in the
# underlying module (mockable at plan/validate).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  platform_tags = merge(
    {
      "platform:system"     = "ml-platform"
      "platform:component"  = "gpu-compute"
      "platform:managed-by" = "terragrunt"
    },
    var.additional_node_tags,
  )

  # Translate the GPU-specific pool config into the karpenter-nodepools contract.
  nodepool_configs = var.enabled ? {
    for name, cfg in var.gpu_pools : name => {
      enabled              = true
      cpu_limit            = cfg.cpu_limit
      memory_limit         = cfg.memory_limit
      spot_percentage      = cfg.spot_percentage
      instance_families    = cfg.instance_families
      instance_sizes       = cfg.instance_sizes
      architectures        = ["amd64"] # NVIDIA GPU pools stay x86 (plan §7 #7).
      consolidation_policy = cfg.consolidation_policy
      consolidate_after    = cfg.consolidate_after
      weight               = cfg.weight
      placement_group_name = cfg.enable_efa ? cfg.placement_group_name : null
      availability_zone    = cfg.enable_efa ? cfg.availability_zone : null
      labels = merge(cfg.extra_labels, {
        "platform.system"    = "ml-platform"
        "platform.component" = "gpu-compute"
        "nvidia.com/gpu"     = "present"
        "efa.enabled"        = tostring(cfg.enable_efa)
      })
      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "present"
          effect = "NoSchedule"
        }
      ]
    }
  } : {}
}

module "karpenter_nodepools" {
  source = "../karpenter-nodepools"

  cluster_name       = var.cluster_name
  node_iam_role_name = var.node_iam_role_name
  ami_family         = var.ami_family
  nodepool_configs   = local.nodepool_configs

  additional_node_tags = local.platform_tags
}
