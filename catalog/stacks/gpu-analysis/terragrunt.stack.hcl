# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Analysis Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys the GPU video analysis EKS infrastructure:
#   gpu-vpc → gpu-placement-group → gpu-eks → gpu-cilium
#                                            → gpu-karpenter-iam → gpu-karpenter-controller
#                                                                 → gpu-karpenter-nodepools
#
# Optimized for real-time video analysis: GPU instances (A10G/T4), placement groups
# for low-latency networking, single-AZ pinning, mixed on-demand/spot capacity.
#
# CNI: Cilium with ENI IPAM mode
# AMI: Bottlerocket (native Cilium support)
#
# Usage (from live tree):
#   cd terragrunt/staging/eu-west-3/gpu-analysis
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

unit "gpu-vpc" {
  source = "${get_repo_root()}/catalog/units/gpu-vpc"
  path   = "gpu-vpc"
}

unit "gpu-placement-group" {
  source = "${get_repo_root()}/catalog/units/gpu-placement-group"
  path   = "gpu-placement-group"
}

unit "gpu-eks" {
  source = "${get_repo_root()}/catalog/units/gpu-eks"
  path   = "gpu-eks"
}

unit "gpu-cilium" {
  source = "${get_repo_root()}/catalog/units/gpu-cilium"
  path   = "gpu-cilium"
}

unit "gpu-karpenter-iam" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-iam"
  path   = "gpu-karpenter-iam"
}

unit "gpu-karpenter-controller" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-controller"
  path   = "gpu-karpenter-controller"
}

unit "gpu-karpenter-nodepools" {
  source = "${get_repo_root()}/catalog/units/gpu-karpenter-nodepools"
  path   = "gpu-karpenter-nodepools"
}
