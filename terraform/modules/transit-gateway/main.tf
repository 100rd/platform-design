# ---------------------------------------------------------------------------------------------------------------------
# AWS Transit Gateway — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# Central hub for inter-VPC and inter-account connectivity.
# Deployed in the network account, shared to workload accounts via RAM.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "this" {
  description = "${var.name} - Transit Gateway"

  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  multicast_support               = var.enable_multicast ? "enable" : "disable"

  tags = merge(var.tags, {
    Name = var.name
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Route Tables
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = var.route_tables

  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Default routes between route tables (prod <-> shared, nonprod <-> shared)
# Cross-env routes are intentionally omitted for isolation
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_route" "blackhole_cross_env" {
  for_each = var.blackhole_cidrs

  destination_cidr_block         = each.value
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.key].id
  blackhole                      = true
}

# ---------------------------------------------------------------------------------------------------------------------
# RAM Share — share the TGW with workload accounts so they can attach VPCs.
# ---------------------------------------------------------------------------------------------------------------------
# Issue #170. The share is created only when at least one principal is supplied.
# Account-level principals (12-digit account IDs) and OU/Org ARNs are both
# accepted as RAM principals — the consuming Terragrunt unit decides which.

resource "aws_ram_resource_share" "tgw" {
  count = length(var.ram_principals) > 0 ? 1 : 0

  name                      = "${var.name}-tgw-share"
  allow_external_principals = false # Stay within the org. Flip to true only for vendor / cross-org integrations.

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-share"
  })
}

resource "aws_ram_resource_association" "tgw" {
  count = length(var.ram_principals) > 0 ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this.arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ram_principal_association" "tgw" {
  for_each = toset(var.ram_principals)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}
