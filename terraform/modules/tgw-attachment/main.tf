# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway VPC Attachment — Workload Accounts
# ---------------------------------------------------------------------------------------------------------------------
# Attaches a VPC to a Transit Gateway (shared via RAM from network account).
# Each workload account attaches its VPCs to enable cross-account connectivity.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.enabled ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  dns_support = "enable"

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-attachment"
  })
}

# Associate with the appropriate route table
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = var.enabled && var.route_table_id != "" ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = var.route_table_id
}

# Propagate routes to the route table
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = var.enabled && var.route_table_id != "" ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_route_table_id = var.route_table_id
}

# Add route in VPC route tables pointing to TGW for cross-account traffic
resource "aws_route" "tgw_routes" {
  for_each = var.enabled ? var.vpc_route_table_ids : {}

  route_table_id         = each.value
  destination_cidr_block = var.tgw_destination_cidr
  transit_gateway_id     = var.transit_gateway_id
}
