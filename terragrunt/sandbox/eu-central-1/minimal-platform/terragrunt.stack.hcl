# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform Stack — sandbox / eu-central-1
# ---------------------------------------------------------------------------------------------------------------------
# Personal AWS sandbox account (007027391583, IAM user igor).
# Uses the same catalog units as the staging/eu-central-1/minimal-platform stack.
#
# Key differences from staging:
#   - Single NAT gateway (cost optimisation — sandbox/account.hcl: single_nat_gateway = true)
#   - EKS API server public but locked to user IP (eks_public_access_cidrs = ["84.40.153.97/32"])
#   - No SSO access entries — IAM user igor is cluster admin via creator permissions
#   - KMS admin/user = IAM user igor (no OrganizationAccountAccessRole)
#   - S3 native state locking (use_lockfile = true) — no DynamoDB lock table
#   - No Transit Gateway, no ClusterMesh, no cross-account log shipping
#
# Deploy order (Round 10.5 split):
#   vpc -> kms -> eks-cluster -> cilium -> eks-nodes -> eks-addons
#
# The eks unit was split into eks-cluster + eks-nodes to break the Cilium
# chicken-and-egg cycle: Cilium is deployed after the control plane but before
# nodes join, so the CNI is ready when nodes first start up.
#
# Usage:
#   terragrunt stack generate
#   terragrunt stack plan   # review before apply
#   terragrunt stack apply  # CI/CD only — never run manually
# ---------------------------------------------------------------------------------------------------------------------

unit "vpc" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-vpc"
  path   = "vpc"
}

unit "kms" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-kms"
  path   = "kms"
}

unit "eks-cluster" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-eks-cluster"
  path   = "eks-cluster"
}

unit "cilium" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-cilium"
  path   = "cilium"
}

unit "eks-nodes" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-eks-nodes"
  path   = "eks-nodes"
}

unit "eks-addons" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-eks-addons"
  path   = "eks-addons"
}
