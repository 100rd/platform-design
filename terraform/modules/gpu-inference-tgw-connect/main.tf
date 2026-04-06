# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference TGW Connect + BGP Peering
# ---------------------------------------------------------------------------------------------------------------------
# Creates AWS Transit Gateway Connect attachment with GRE tunnels and BGP
# peering configuration for Cilium native routing. Each Connect peer represents
# a BGP session between the gpu-inference cluster and TGW.
# ---------------------------------------------------------------------------------------------------------------------

# TGW Connect Peers for BGP sessions (one per AZ for HA)
resource "aws_ec2_transit_gateway_connect_peer" "this" {
  for_each = var.bgp_peers

  transit_gateway_attachment_id = var.tgw_connect_attachment_id
  peer_address                  = each.value.peer_address
  transit_gateway_address       = each.value.tgw_address
  bgp_asn                       = each.value.bgp_asn
  inside_cidr_blocks            = each.value.inside_cidr_blocks

  tags = merge(var.tags, {
    Name = "${var.name}-peer-${each.key}"
    AZ   = each.value.availability_zone
  })
}

# Static route for Pod CIDR as fallback (if BGP flaps)
resource "aws_ec2_transit_gateway_route" "pod_cidr_fallback" {
  count = var.enable_static_fallback ? 1 : 0

  destination_cidr_block         = var.pod_cidr
  transit_gateway_attachment_id  = var.tgw_connect_attachment_id
  transit_gateway_route_table_id = var.tgw_route_table_id
}

# Propagate Pod CIDR to shared route table for cross-cluster communication
resource "aws_ec2_transit_gateway_route_table_propagation" "shared" {
  count = var.shared_route_table_id != "" ? 1 : 0

  transit_gateway_attachment_id  = var.tgw_connect_attachment_id
  transit_gateway_route_table_id = var.shared_route_table_id
}
