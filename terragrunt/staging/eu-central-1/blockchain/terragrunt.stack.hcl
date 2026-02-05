# ---------------------------------------------------------------------------------------------------------------------
# Blockchain HPC Stack — Live Deployment (staging/eu-central-1)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the blockchain HPC EKS infrastructure for this environment and region.
# Environment-specific values come from account.hcl; region-specific from region.hcl.
#
# Usage:
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

unit "blockchain-vpc" {
  source = "${get_repo_root()}/catalog/units/blockchain-vpc"
  path   = "blockchain-vpc"
}

unit "placement-group" {
  source = "${get_repo_root()}/catalog/units/placement-group"
  path   = "placement-group"
}

unit "blockchain-eks" {
  source = "${get_repo_root()}/catalog/units/blockchain-eks"
  path   = "blockchain-eks"
}

unit "blockchain-cilium" {
  source = "${get_repo_root()}/catalog/units/blockchain-cilium"
  path   = "blockchain-cilium"
}

unit "blockchain-karpenter-iam" {
  source = "${get_repo_root()}/catalog/units/blockchain-karpenter-iam"
  path   = "blockchain-karpenter-iam"
}

unit "blockchain-karpenter-controller" {
  source = "${get_repo_root()}/catalog/units/blockchain-karpenter-controller"
  path   = "blockchain-karpenter-controller"
}

unit "blockchain-karpenter-nodepools" {
  source = "${get_repo_root()}/catalog/units/blockchain-karpenter-nodepools"
  path   = "blockchain-karpenter-nodepools"
}
