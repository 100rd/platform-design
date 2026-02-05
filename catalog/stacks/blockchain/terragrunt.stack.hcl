# ---------------------------------------------------------------------------------------------------------------------
# Blockchain HPC Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys the blockchain HPC EKS infrastructure:
#   blockchain-vpc → placement-group → blockchain-eks → blockchain-cilium
#                                                     → blockchain-karpenter-iam → blockchain-karpenter-controller
#                                                                                → blockchain-karpenter-nodepools
#
# Optimized for Ethereum workloads: low-latency networking via placement groups,
# Nitro/ENA-optimized instances, single-AZ pinning, and on-demand-only capacity.
#
# CNI: Cilium with ENI IPAM mode
# AMI: Bottlerocket (native Cilium support)
#
# Usage (from live tree):
#   cd terragrunt/staging/eu-central-1/blockchain
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
