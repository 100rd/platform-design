# ---------------------------------------------------------------------------------------------------------------------
# Platform Stack Template
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys the full platform infrastructure:
#   VPC → EKS → Karpenter + Monitoring + RDS
#
# Each unit reads its environment-specific configuration from account.hcl and region.hcl
# in the live tree. Dependencies between units are resolved automatically by Terragrunt.
#
# Usage (from live tree):
#   cd terragrunt/dev/eu-west-1/platform
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

unit "vpc" {
  source = "${get_repo_root()}/catalog/units/vpc"
  path   = "vpc"
}

unit "secrets" {
  source = "${get_repo_root()}/catalog/units/secrets"
  path   = "secrets"
}

unit "eks" {
  source = "${get_repo_root()}/catalog/units/eks"
  path   = "eks"
}

unit "karpenter" {
  source = "${get_repo_root()}/catalog/units/karpenter"
  path   = "karpenter"
}

unit "rds" {
  source = "${get_repo_root()}/catalog/units/rds"
  path   = "rds"
}

unit "monitoring" {
  source = "${get_repo_root()}/catalog/units/monitoring"
  path   = "monitoring"
}
