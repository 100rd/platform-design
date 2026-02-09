# ---------------------------------------------------------------------------------------------------------------------
# Cilium ClusterMesh Security Group Rules
# ---------------------------------------------------------------------------------------------------------------------
# Adds ingress rules to the EKS node security group for cross-cluster ClusterMesh
# traffic. Each peer VPC CIDR gets rules for the four required ports:
#   - TCP 2379: ClusterMesh etcd API (kvstore mesh)
#   - TCP 4240: Cilium health checks
#   - UDP 51871: WireGuard encrypted tunnel
#   - TCP 4244: Hubble relay (observability)
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Build flat map of region x port combinations
  sg_rules = { for pair in flatten([
    for region, cidr in var.peer_vpc_cidrs : [
      {
        key         = "${region}-etcd-api"
        cidr        = cidr
        from_port   = 2379
        to_port     = 2379
        protocol    = "tcp"
        description = "ClusterMesh etcd API from ${region}"
      },
      {
        key         = "${region}-cilium-health"
        cidr        = cidr
        from_port   = 4240
        to_port     = 4240
        protocol    = "tcp"
        description = "Cilium health checks from ${region}"
      },
      {
        key         = "${region}-wireguard"
        cidr        = cidr
        from_port   = 51871
        to_port     = 51871
        protocol    = "udp"
        description = "WireGuard encrypted tunnel from ${region}"
      },
      {
        key         = "${region}-hubble-relay"
        cidr        = cidr
        from_port   = 4244
        to_port     = 4244
        protocol    = "tcp"
        description = "Hubble relay from ${region}"
      },
    ]
  ]) : pair.key => pair }
}

resource "aws_vpc_security_group_ingress_rule" "clustermesh" {
  for_each = var.enabled ? local.sg_rules : {}

  security_group_id = var.node_security_group_id
  cidr_ipv4         = each.value.cidr
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  description       = each.value.description

  tags = merge(var.tags, {
    Name = "clustermesh-${each.key}"
  })
}
