locals {
  account_name   = "network"
  account_id     = "555555555555" # TODO: Replace with actual AWS network account ID
  aws_account_id = "555555555555"
  environment    = "network"
  email          = "aws+network@example.com"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-network"

  # Organization context
  org_account_type   = "network"
  org_ou             = "Infrastructure"
  management_account = "000000000000"
  organization_arn   = "" # Populated after org creation

  # NAT Gateway — HA for reliability
  single_nat_gateway = false

  # TGW configuration (blackhole routes for environment isolation)
  tgw_blackhole_cidrs = {}

  # Transit Gateway peering configuration
  enable_tgw_peering = true
  tgw_peers = {
    "eu-central-1" = { tgw_id = "", cidrs = ["10.13.0.0/16"] }
    "eu-west-1"    = { tgw_id = "", cidrs = ["10.10.0.0/16"] }
  }

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

  # ---------------------------------------------------------------------------
  # ADR-0013 — Inter-VPC access security model
  # ---------------------------------------------------------------------------
  # Remote-access VPN trust sub-pools (representative placeholder ranges). The
  # ops sub-pool is the only tier routed to production; the standard sub-pool
  # reaches the shared range only. Override these per estate as needed.
  remote_access_vpn = {
    vpn_client_cidr           = "10.100.0.0/20"
    vpn_ops_subpool_cidr      = "10.100.0.0/24"
    vpn_standard_subpool_cidr = "10.100.1.0/24"

    # Per-CIDR egress allow-list on the VPN instance SG. Must agree with the
    # inter_vpc_security.vpn_forward_routes below.
    reachable_cidrs = [
      # "10.10.0.0/16",  # shared
      # "10.30.0.0/16",  # production (ops only — see TGW asymmetric return)
    ]
  }

  # Inter-VPC TGW segmentation + legacy-side routes + prod NACL backstop.
  #
  # SEQUENCING GATE: keep enable_vpn_routing = false until (1) the network VPC +
  # attachment are applied AND (2) enable_prod_nacl_backstop is applied —
  # otherwise the standard sub-pool transiently reaches prod via the TGW.
  inter_vpc_security = {
    enable_vpn_routing = false
    network_vpc_id     = "" # set to the network VPN VPC ID before enabling routing

    # Outbound allow-list. tgw_attachment_id is either a new-estate spoke
    # attachment or the LEGACY admin-VPC's existing attachment (the cross-estate
    # join — legacy-side routes). Placeholders; fill with real IDs out-of-band.
    vpn_forward_routes = {
      # shared       = { destination_cidr = "10.10.0.0/16",  tgw_attachment_id = "tgw-attach-shared" }
      # production   = { destination_cidr = "10.30.0.0/16",  tgw_attachment_id = "tgw-attach-prod" }
      # legacy-admin = { destination_cidr = "172.21.0.0/16", tgw_attachment_id = "tgw-attach-legacy-admin" }
    }

    # Return routes. PROD-tier RTs return ONLY to the ops sub-pool (asymmetric
    # return); shared/dev-tier RTs return the full pool.
    vpn_return_routes = {
      # production = { route_table_id = "tgw-rtb-prod",   vpn_pool_cidr = "10.100.0.0/24" }
      # shared     = { route_table_id = "tgw-rtb-shared", vpn_pool_cidr = "10.100.0.0/20" }
    }

    # Prod NACL backstop (ADR-0013 design-target, prod-account scoped). Apply
    # this BEFORE flipping enable_vpn_routing. NACL IDs come from the prod VPC.
    enable_prod_nacl_backstop = false
    prod_subnet_nacl_ids      = [] # e.g. ["acl-xxxx", "acl-yyyy"]
  }
}
