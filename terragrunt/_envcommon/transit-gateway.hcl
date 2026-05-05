# -----------------------------------------------------------------------------
# _envcommon: Transit Gateway module — shared inputs and source pin
# -----------------------------------------------------------------------------
# Lives in the network account. This file fixes TGW defaults; per-region units
# only specify the region and any spoke-specific overrides.
#
# See issue #170 for hub-and-spoke design and #171 for inspection-VPC wiring.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/transit-gateway"

  defaults = {
    # AS number from RFC 6996 private range; per-region offsets keep BGP
    # neighbours unique across the 4-region footprint.
    amazon_side_asn_base = 64512

    # Default route-table modes: explicit propagation/association so that
    # spoke isolation is the default and exceptions are visible.
    default_route_table_association = "disable"
    default_route_table_propagation = "disable"

    # Cross-account sharing via RAM enabled by default — the platform
    # operates one TGW shared with workload accounts.
    auto_accept_shared_attachments = "enable"

    # Multicast and DNS support default off; flip per env if needed.
    multicast_support = "disable"
    dns_support       = "enable"
    vpn_ecmp_support  = "enable"

    # Centralized inspection VPC route table topology — see #171.
    create_inspection_route_table = true
  }
}

terraform {
  source = local.module_source
}

inputs = {
  amazon_side_asn_base            = local.defaults.amazon_side_asn_base
  default_route_table_association = local.defaults.default_route_table_association
  default_route_table_propagation = local.defaults.default_route_table_propagation
  auto_accept_shared_attachments  = local.defaults.auto_accept_shared_attachments
  multicast_support               = local.defaults.multicast_support
  dns_support                     = local.defaults.dns_support
  vpn_ecmp_support                = local.defaults.vpn_ecmp_support
  create_inspection_route_table   = local.defaults.create_inspection_route_table
}
