# ---------------------------------------------------------------------------------------------------------------------
# Inter-VPC Access Security — TGW segmentation + cross-estate VPN join (ADR-0013)
# ---------------------------------------------------------------------------------------------------------------------
# Implements ADR-0013's inter-VPC trust model on the hub Transit Gateway:
#
#   Layer 1 (primary)  — TGW route-table segmentation: deny-by-default custom
#                         route tables; the VPN attachment reaches only the
#                         spokes its allow-list permits; asymmetric return
#                         routes keep the standard sub-pool out of prod.
#   Legacy-side routes  — the cross-estate join: routes to the legacy admin /
#                         analytics ranges are added on the VPN route table via
#                         the legacy admin-VPC's existing TGW attachment. No new
#                         VPC peering is created (ADR-0005 / ADR-0013 Alt A).
#   Prod NACL backstop  — prod subnets deny the standard VPN sub-pool while
#                         allowing the ops sub-pool (ADR-0013 Layer 3,
#                         design-target). Optional, prod-account scoped.
#
# IMPORTANT: TGW route tables filter by DESTINATION, not source IP within an
# attachment. The ops/standard split is enforced by three layered controls:
#   (a) VPN route-push — ops/standard profiles advertise different CIDRs;
#   (b) prod NACL backstop — prod subnets deny the standard sub-pool;
#   (c) asymmetric return routes (here) — prod-tier RTs return ONLY to the ops
#       sub-pool, so standard-tier clients have no TGW return path from prod.
#
# Sequencing gate: `enable_vpn_routing = true` must be flipped ONLY AFTER the
# network VPC + attachment are applied AND the prod NACL backstop is in place,
# otherwise the standard sub-pool transiently reaches prod via the TGW.
# Default is false.
# ---------------------------------------------------------------------------------------------------------------------

# ─── VPN attachment lookup ────────────────────────────────────────────────────
# The new-estate Network VPC (VPN host) attachment. Guarded by enable_vpn_routing.
data "aws_ec2_transit_gateway_vpc_attachment" "network_vpn" {
  count = var.enable_vpn_routing ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.network_vpc_id]
  }
  filter {
    name   = "transit-gateway-id"
    values = [var.transit_gateway_id]
  }
}

# Network VPN route table — the VPN attachment's own isolated RT. Lists only the
# destinations VPN clients may reach (ADR-0013 allow-list, no default route).
resource "aws_ec2_transit_gateway_route_table" "network_vpn" {
  count = var.enable_vpn_routing ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  tags               = merge(var.tags, { Name = "${var.name}-network-vpn-tgw-rt" })
}

resource "aws_ec2_transit_gateway_route_table_association" "network_vpn" {
  count = var.enable_vpn_routing ? 1 : 0

  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_vpc_attachment.network_vpn[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.network_vpn[0].id
}

# ─── Network VPN RT: outbound allow-list (forward routes) ─────────────────────
# One forward route per permitted destination. The destination_cidr_block /
# attachment pairs come from var.vpn_forward_routes so no estate-specific CIDR
# is hardcoded — callers pass representative/placeholder ranges.
#
# vpn_forward_routes is a map of:
#   <key> = { destination_cidr = "<cidr>", tgw_attachment_id = "<tgw-attach-id>" }
# where tgw_attachment_id is either a new-estate spoke attachment or the legacy
# admin-VPC's existing attachment (the cross-estate join — legacy-side routes).
resource "aws_ec2_transit_gateway_route" "vpn_forward" {
  for_each = var.enable_vpn_routing ? var.vpn_forward_routes : {}

  destination_cidr_block         = each.value.destination_cidr
  transit_gateway_attachment_id  = each.value.tgw_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.network_vpn[0].id
}

# ─── Return routes: spoke RTs -> VPN pool (asymmetric — control c) ────────────
# Prod-tier route tables return ONLY to the ops sub-pool. Shared/dev-tier route
# tables return the full VPN pool. var.vpn_return_routes is a map of:
#   <key> = {
#     route_table_id = "<tgw-rtb-id>"   # the spoke RT to add the return route to
#     vpn_pool_cidr  = "<cidr>"         # ops sub-pool for prod RTs; full /20 for shared
#   }
# The VPN attachment is the next hop for every return route.
resource "aws_ec2_transit_gateway_route" "vpn_return" {
  for_each = var.enable_vpn_routing ? var.vpn_return_routes : {}

  destination_cidr_block         = each.value.vpn_pool_cidr
  transit_gateway_attachment_id  = data.aws_ec2_transit_gateway_vpc_attachment.network_vpn[0].id
  transit_gateway_route_table_id = each.value.route_table_id
}

# ─── Prod NACL backstop (ADR-0013 Layer 3 — design-target) ────────────────────
# Stateless subnet-level deny for the standard VPN sub-pool on prod subnets,
# behind the TGW allow-list. The ops sub-pool is explicitly allowed at a lower
# rule number so it is evaluated first. This is the prod-account VPC unit
# (cross-account follow-up); enabled independently of enable_vpn_routing so the
# backstop can be applied BEFORE routing is switched on (the sequencing gate).
#
# rule numbers (lower = evaluated first):
#   100  ALLOW  ops sub-pool        (so ops is never caught by the deny below)
#   110  DENY   standard sub-pool   (the backstop)
# Both are applied to every prod subnet NACL passed in var.prod_subnet_nacl_ids.

resource "aws_network_acl_rule" "prod_allow_ops_subpool" {
  for_each = var.enable_prod_nacl_backstop ? toset(var.prod_subnet_nacl_ids) : toset([])

  network_acl_id = each.value
  rule_number    = var.nacl_ops_allow_rule_number
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpn_ops_subpool_cidr
}

resource "aws_network_acl_rule" "prod_deny_standard_subpool" {
  for_each = var.enable_prod_nacl_backstop ? toset(var.prod_subnet_nacl_ids) : toset([])

  network_acl_id = each.value
  rule_number    = var.nacl_standard_deny_rule_number
  egress         = false
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = var.vpn_standard_subpool_cidr
}
