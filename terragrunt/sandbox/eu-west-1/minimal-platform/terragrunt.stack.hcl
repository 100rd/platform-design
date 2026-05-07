# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform Stack — sandbox / eu-west-1
# ---------------------------------------------------------------------------------------------------------------------
# Personal AWS sandbox account (007027391583, IAM user igor).
# Uses the same catalog units as the staging/eu-central-1/minimal-platform stack.
#
# eu-west-1 is used for Round 11 redeployment to avoid the 3 KMS keys in
# PendingDeletion state in eu-central-1 (deletion window expires 2026-05-14).
#
# Key differences from staging:
#   - Single NAT gateway (cost optimisation — sandbox/account.hcl: single_nat_gateway = true)
#   - EKS API server public but locked to user IP (eks_public_access_cidrs = ["84.40.153.97/32"])
#   - No SSO access entries — IAM user igor is cluster admin via creator permissions
#   - KMS admin/user = IAM user igor (no OrganizationAccountAccessRole)
#   - S3 native state locking (use_lockfile = true) — no DynamoDB lock table
#   - No Transit Gateway, no ClusterMesh, no cross-account log shipping
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

unit "eks" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-eks"
  path   = "eks"
}

unit "cilium" {
  source = "${get_repo_root()}/catalog/units/minimal-platform-cilium"
  path   = "cilium"
}
