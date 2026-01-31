# ---------------------------------------------------------------------------------------------------------------------
# Connectivity Stack — Live Deployment (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys centralized networking infrastructure for this region.
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

unit "transit-gateway" {
  source = "${get_repo_root()}/catalog/units/transit-gateway"
  path   = "transit-gateway"
}

unit "ram-share" {
  source = "${get_repo_root()}/catalog/units/ram-share"
  path   = "ram-share"
}

unit "tgw-route-tables" {
  source = "${get_repo_root()}/catalog/units/tgw-route-tables"
  path   = "tgw-route-tables"
}

unit "vpn-connection" {
  source = "${get_repo_root()}/catalog/units/vpn-connection"
  path   = "vpn-connection"
}

unit "route53-resolver" {
  source = "${get_repo_root()}/catalog/units/route53-resolver"
  path   = "route53-resolver"
}
