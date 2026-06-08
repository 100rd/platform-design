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

# ADR-0013 — Inter-VPC access security model: remote-access VPN host (Network
# account, joined to the TGW estate) + TGW segmentation / legacy-side routes /
# prod NACL backstop. inter-vpc-security depends on remote-access-vpn for the
# trust sub-pool CIDRs and on transit-gateway for the hub TGW.
unit "remote-access-vpn" {
  source = "${get_repo_root()}/catalog/units/remote-access-vpn"
  path   = "remote-access-vpn"
}

unit "inter-vpc-security" {
  source = "${get_repo_root()}/catalog/units/inter-vpc-security"
  path   = "inter-vpc-security"
}
