# ---------------------------------------------------------------------------------------------------------------------
# Site-to-Site VPN Connection — Network Account
# ---------------------------------------------------------------------------------------------------------------------
# Creates VPN connections to 3rd-party partners or on-premises networks.
# Terminates on the Transit Gateway for centralized routing.
# ---------------------------------------------------------------------------------------------------------------------

# Customer Gateway (the remote side)
resource "aws_customer_gateway" "this" {
  for_each = var.vpn_connections

  bgp_asn    = each.value.bgp_asn
  ip_address = each.value.remote_ip
  type       = "ipsec.1"

  certificate_arn = try(each.value.certificate_arn, null)

  tags = merge(var.tags, {
    Name = "${var.name}-cgw-${each.key}"
  })
}

# VPN Connection
resource "aws_vpn_connection" "this" {
  for_each = var.vpn_connections

  customer_gateway_id = aws_customer_gateway.this[each.key].id
  transit_gateway_id  = var.transit_gateway_id
  type                = "ipsec.1"

  static_routes_only = each.value.static_routes_only

  tunnel1_inside_cidr   = try(each.value.tunnel1_inside_cidr, null)
  tunnel2_inside_cidr   = try(each.value.tunnel2_inside_cidr, null)
  tunnel1_preshared_key = try(each.value.tunnel1_psk, null)
  tunnel2_preshared_key = try(each.value.tunnel2_psk, null)

  tags = merge(var.tags, {
    Name    = "${var.name}-vpn-${each.key}"
    Partner = each.key
  })
}

# Static routes (if not using BGP)
resource "aws_vpn_connection_route" "this" {
  for_each = { for item in flatten([
    for vpn_name, vpn in var.vpn_connections : [
      for cidr in try(vpn.static_routes, []) : {
        key    = "${vpn_name}-${cidr}"
        vpn_id = vpn_name
        cidr   = cidr
      }
    ] if vpn.static_routes_only
  ]) : item.key => item }

  vpn_connection_id      = aws_vpn_connection.this[each.value.vpn_id].id
  destination_cidr_block = each.value.cidr
}
