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
