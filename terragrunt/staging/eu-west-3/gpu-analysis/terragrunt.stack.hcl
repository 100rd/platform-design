# ---------------------------------------------------------------------------------------------------------------------
# GPU Video Analysis Stack — Live Deployment (staging/eu-west-3)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the GPU video analysis EKS infrastructure for this environment and region.
# Environment-specific values come from account.hcl; region-specific from region.hcl.
#
# Usage:
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
