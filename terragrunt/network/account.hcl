locals {
  account_name   = "network"
  account_id     = "555555555555" # TODO: Replace with actual AWS network account ID
  aws_account_id = "555555555555"
  environment    = "network"

  # Organization context
  org_account_type   = "network"
  org_ou             = "Infrastructure"
  management_account = "000000000000"
  organization_arn   = "" # Populated after org creation

  # NAT Gateway — HA for reliability
  single_nat_gateway = false

  # TGW configuration (blackhole routes for environment isolation)
  tgw_blackhole_cidrs = {}

  # VPN connections (3rd-party integrations)
  vpn_connections = {
    # Example:
    # partner-datacenter = {
    #   remote_ip          = "203.0.113.1"
    #   bgp_asn            = 65001
    #   static_routes_only = false
    # }
  }

  # DNS forwarding rules (resolve partner/on-prem domains)
  dns_forwarding_rules = {
    # Example:
    # partner-internal = {
    #   domain = "internal.partner.com"
    #   target_ips = [
    #     { ip = "10.100.0.53" },
    #     { ip = "10.100.1.53" },
    #   ]
    # }
  }
}
