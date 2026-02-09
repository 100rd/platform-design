# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway Peering — Cross-Region
# ---------------------------------------------------------------------------------------------------------------------
# Creates a TGW peering attachment between two regions and adds routes for
# remote CIDRs in each local TGW route table. The accepter uses a provider
# alias for the peer region so both sides are managed in one module.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Build a flat map of route-table x cidr combinations for route creation
  route_entries = { for pair in flatten([
    for rt_name, rt_id in var.local_route_table_ids : [
      for cidr in var.peer_cidrs : {
        key            = "${rt_name}--${cidr}"
        route_table_id = rt_id
        cidr           = cidr
      }
    ]
  ]) : pair.key => pair }
}

# ---------------------------------------------------------------------------------------------------------------------
# Peering Attachment (requester side — local region)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  count = var.enabled ? 1 : 0

  transit_gateway_id      = var.local_tgw_id
  peer_transit_gateway_id = var.peer_tgw_id
  peer_region             = var.peer_region
  peer_account_id         = var.peer_account_id

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-peering"
    Side = "requester"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Peering Attachment Accepter (peer region — uses aliased provider)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  count = var.enabled ? 1 : 0

  provider = aws.peer

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this[0].id

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-peering"
    Side = "accepter"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# TGW Routes — route peer CIDRs through the peering attachment in each local route table
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_route" "peer_cidrs" {
  for_each = var.enabled ? local.route_entries : {}

  destination_cidr_block         = each.value.cidr
  transit_gateway_route_table_id = each.value.route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this[0].id
}
