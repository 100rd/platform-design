# ---------------------------------------------------------------------------------------------------------------------
# GPU Inference VPC — Terraform Module
# ---------------------------------------------------------------------------------------------------------------------
# Dedicated VPC for the gpu-inference EKS cluster with BGP-native routing
# via AWS Transit Gateway Connect. Designed for up to 5000 GPU nodes using
# a separate Pod CIDR (100.64.0.0/10) announced via BGP, avoiding ENI IP
# limits and VPC route table constraints.
# ---------------------------------------------------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  intra_subnets   = var.intra_subnets

  # No public subnets — all traffic via TGW or NAT
  public_subnets = []

  # NAT Gateway for outbound internet (image pulls, API calls)
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs — audit and forensics
  enable_flow_log                                 = true
  flow_log_destination_type                       = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group            = true
  flow_log_cloudwatch_log_group_retention_in_days = 365
  flow_log_max_aggregation_interval               = 60
  flow_log_traffic_type                           = "ALL"

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  intra_subnet_tags = {
    "Role" = "gpu-node-interconnect"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Transit Gateway Connect Attachment
# ---------------------------------------------------------------------------------------------------------------------
# TGW Connect provides BGP peering over GRE tunnels, enabling Cilium nodes
# to advertise the Pod CIDR (100.64.0.0/10) directly to the transit gateway.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.transit_gateway_id != "" ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnets

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  dns_support = "enable"

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-attachment"
  })
}

resource "aws_ec2_transit_gateway_connect" "this" {
  count = var.transit_gateway_id != "" ? 1 : 0

  transport_attachment_id = aws_ec2_transit_gateway_vpc_attachment.this[0].id
  transit_gateway_id      = var.transit_gateway_id
  protocol                = "gre"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name = "${var.name}-tgw-connect"
  })
}

# Route table association for the TGW Connect attachment
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  count = var.transit_gateway_id != "" && var.tgw_route_table_id != "" ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect.this[0].id
  transit_gateway_route_table_id = var.tgw_route_table_id
}

# Route table propagation for the TGW Connect attachment
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  count = var.transit_gateway_id != "" && var.tgw_route_table_id != "" ? 1 : 0

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_connect.this[0].id
  transit_gateway_route_table_id = var.tgw_route_table_id
}

# VPC routes pointing to TGW for cross-account traffic
resource "aws_route" "tgw_routes" {
  for_each = var.transit_gateway_id != "" ? { for i, rt in module.vpc.private_route_table_ids : "private-${i}" => rt } : {}

  route_table_id         = each.value
  destination_cidr_block = var.tgw_destination_cidr
  transit_gateway_id     = var.transit_gateway_id
}

# ---------------------------------------------------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------------------------------------------------

# GPU node-to-node communication (NCCL, RDMA, all-reduce)
resource "aws_security_group" "gpu_interconnect" {
  name_prefix = "${var.name}-gpu-interconnect-"
  description = "GPU node-to-node communication for NCCL and RDMA"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-gpu-interconnect"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow all traffic within the GPU interconnect security group
resource "aws_vpc_security_group_ingress_rule" "gpu_self" {
  security_group_id            = aws_security_group.gpu_interconnect.id
  referenced_security_group_id = aws_security_group.gpu_interconnect.id
  ip_protocol                  = "-1"
  description                  = "All traffic between GPU nodes (NCCL/RDMA)"
}

resource "aws_vpc_security_group_egress_rule" "gpu_self" {
  security_group_id            = aws_security_group.gpu_interconnect.id
  referenced_security_group_id = aws_security_group.gpu_interconnect.id
  ip_protocol                  = "-1"
  description                  = "All traffic between GPU nodes (NCCL/RDMA)"
}

# Allow outbound to all (NAT gateway for image pulls, API calls)
resource "aws_vpc_security_group_egress_rule" "gpu_egress_all" {
  security_group_id = aws_security_group.gpu_interconnect.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound internet access via NAT"
}

# BGP and GRE security group for TGW Connect peering
resource "aws_security_group" "bgp_gre" {
  name_prefix = "${var.name}-bgp-gre-"
  description = "BGP and GRE for TGW Connect peering"
  vpc_id      = module.vpc.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-bgp-gre"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# BGP (TCP/179) ingress from VPC CIDR
resource "aws_vpc_security_group_ingress_rule" "bgp_ingress" {
  security_group_id = aws_security_group.bgp_gre.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 179
  to_port           = 179
  ip_protocol       = "tcp"
  description       = "BGP peering"
}

# GRE (protocol 47) ingress from VPC CIDR
resource "aws_vpc_security_group_ingress_rule" "gre_ingress" {
  security_group_id = aws_security_group.bgp_gre.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "47"
  description       = "GRE tunnels for TGW Connect"
}

# BGP + GRE egress
resource "aws_vpc_security_group_egress_rule" "bgp_egress" {
  security_group_id = aws_security_group.bgp_gre.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound for BGP and GRE"
}

# ---------------------------------------------------------------------------------------------------------------------
# Network ACLs for BGP and GRE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_network_acl" "gpu_private" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = merge(var.tags, {
    Name = "${var.name}-gpu-private"
  })
}

# Allow all inbound from VPC CIDR
resource "aws_network_acl_rule" "private_inbound_vpc" {
  network_acl_id = aws_network_acl.gpu_private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# Allow BGP (TCP/179) from any (TGW endpoints)
resource "aws_network_acl_rule" "private_inbound_bgp" {
  network_acl_id = aws_network_acl.gpu_private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 179
  to_port        = 179
}

# Allow GRE (protocol 47) from any (TGW endpoints)
resource "aws_network_acl_rule" "private_inbound_gre" {
  network_acl_id = aws_network_acl.gpu_private.id
  rule_number    = 120
  egress         = false
  protocol       = "47"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# Allow return traffic (ephemeral ports)
resource "aws_network_acl_rule" "private_inbound_ephemeral" {
  network_acl_id = aws_network_acl.gpu_private.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Allow all outbound
resource "aws_network_acl_rule" "private_outbound_all" {
  network_acl_id = aws_network_acl.gpu_private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}
