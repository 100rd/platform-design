# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform Stack — staging / eu-central-1
# ---------------------------------------------------------------------------------------------------------------------
# A cost-optimised EKS + Cilium platform for staging use cases that do not require
# the full platform stack (no RDS, no Karpenter, no monitoring, no NLB ingress).
#
# Key differences from the standard platform stack:
#   - Single NAT gateway (saves ~$65/mo vs one-per-AZ)
#   - Dedicated VPC CIDR 10.14.0.0/16 (platform stack uses 10.13.0.0/16)
#   - Cluster name: staging-eu-central-1-minimal-platform
#   - KMS aliases: alias/staging-minimal-platform/<key> (no collision with platform)
#   - ClusterMesh disabled (this stack is standalone, not part of the multi-region mesh)
#
# Each unit is backed by a dedicated catalog unit rather than the shared platform
# catalog units, following the established pattern (cf. blockchain stack). This
# avoids coupling the shared units to stack-specific overrides.
#
# Usage:
#   terragrunt stack plan
#   terragrunt stack apply   # CI/CD only — never run manually
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
