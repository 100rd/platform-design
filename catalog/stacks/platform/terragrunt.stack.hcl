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

unit "karpenter-iam" {
  source = "${get_repo_root()}/catalog/units/karpenter-iam"
  path   = "karpenter-iam"
}

unit "karpenter-controller" {
  source = "${get_repo_root()}/catalog/units/karpenter-controller"
  path   = "karpenter-controller"
}

unit "karpenter-nodepools" {
  source = "${get_repo_root()}/catalog/units/karpenter-nodepools"
  path   = "karpenter-nodepools"
}

unit "keda" {
  source = "${get_repo_root()}/catalog/units/keda"
  path   = "keda"
}

unit "hpa-defaults" {
  source = "${get_repo_root()}/catalog/units/hpa-defaults"
  path   = "hpa-defaults"
}

unit "wpa" {
  source = "${get_repo_root()}/catalog/units/wpa"
  path   = "wpa"
}

unit "rds" {
  source = "${get_repo_root()}/catalog/units/rds"
  path   = "rds"
}

unit "monitoring" {
  source = "${get_repo_root()}/catalog/units/monitoring"
  path   = "monitoring"
}
