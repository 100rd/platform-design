# ---------------------------------------------------------------------------------------------------------------------
# Platform Stack — Live Deployment
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the full platform infrastructure for this environment and region.
# Environment-specific values come from account.hcl; region-specific from region.hcl.
#
# Usage:
#   terragrunt stack plan
#   terragrunt stack apply
# ---------------------------------------------------------------------------------------------------------------------

unit "vpc" {
  source = "${get_repo_root()}/catalog/units/vpc"
  path   = "vpc"
}

unit "tgw-attachment" {
  source = "${get_repo_root()}/catalog/units/tgw-attachment"
  path   = "tgw-attachment"
}

unit "secrets" {
  source = "${get_repo_root()}/catalog/units/secrets"
  path   = "secrets"
}

unit "eks" {
  source = "${get_repo_root()}/catalog/units/eks"
  path   = "eks"
}

unit "cilium" {
  source = "${get_repo_root()}/catalog/units/cilium"
  path   = "cilium"
}

unit "clustermesh-sg-rules" {
  source = "${get_repo_root()}/catalog/units/clustermesh-sg-rules"
  path   = "clustermesh-sg-rules"
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

unit "nlb-ingress" {
  source = "${get_repo_root()}/catalog/units/nlb-ingress"
  path   = "nlb-ingress"
}
