# ---------------------------------------------------------------------------------------------------------------------
# Connectivity Stack Template — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# Composable stack that deploys centralized networking infrastructure:
#   VPC → Transit Gateway → RAM Share + Route Tables + VPN + DNS Resolver
#
# Deployed in the network account, shared to workload accounts via RAM.
#
# Usage (from network account live tree):
#   cd terragrunt/network/eu-west-1/connectivity
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
