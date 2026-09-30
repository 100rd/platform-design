# ---------------------------------------------------------------------------------------------------------------------
# aws-eks-gpu-vpc — Greenfield GPU VPC for the AWS EKS GPU ML platform (ADR-0044 D5, ADR-0045 D1)
# ---------------------------------------------------------------------------------------------------------------------
# Mirrors gcp-gpu-vpc: a dedicated VPC for the greenfield aws-eks-gpu cluster with
#   * jumbo-frame (MTU 9001) GPU subnets for EFA / GPUDirect RDMA (ADR-0045 D1)
#   * a single-AZ GPU subnet for EFA cluster placement groups (cannot span AZs)
#   * a self-referencing all-traffic EFA security group (intra-PG GPU<->GPU RDMA)
#   * Karpenter/ELB discovery subnet tags
#
# The whole module is gated by var.enabled (default OFF) so the apply gate is never
# crossed implicitly — nothing is provisioned until a human flips it on.
#
# ADR-0028: every resource carries the platform:* taxonomy via var.tags.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  create = var.enabled

  # ADR-0028 baseline tags merged with caller-supplied platform:* keys.
  base_tags = merge(
    {
      "platform:system"     = "ml-platform"
      "platform:component"  = "gpu-network"
      "platform:managed-by" = "terragrunt"
    },
    var.tags,
  )

  # NAT (and therefore the public subnets that host it) is only created when the
  # caller supplies public subnet CIDRs. Otherwise the VPC is intra/private-only
  # (egress via VPC endpoints), avoiding the upstream module's NAT-without-public
  # constraint.
  enable_nat = length(var.public_subnets) > 0
}

# ---------------------------------------------------------------------------------------------------------------------
# VPC (reuses the battle-tested terraform-aws-modules/vpc, as gpu-inference-vpc does).
# ---------------------------------------------------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  count = local.create ? 1 : 0

  name = var.name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  # GPU subnets are modeled as intra subnets (no NAT, internal GPU interconnect).
  intra_subnets  = var.gpu_subnets
  public_subnets = var.public_subnets

  # NAT only when public subnets host it; intra-only otherwise (VPC endpoints).
  enable_nat_gateway     = local.enable_nat
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                                 = true
  flow_log_destination_type                       = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group            = true
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days
  flow_log_max_aggregation_interval               = 60
  flow_log_traffic_type                           = "ALL"

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  # GPU interconnect subnets — tagged for Karpenter discovery + jumbo-frame intent.
  intra_subnet_tags = {
    "Role"                   = "gpu-node-interconnect"
    "karpenter.sh/discovery" = var.cluster_name
    "platform:mtu"           = tostring(var.mtu)
  }

  tags = local.base_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# EFA security group — EFA requires a self-referencing all-traffic SG so that all GPU
# nodes in a cluster placement group can speak EFA/RDMA to one another (ADR-0045 D1/D4).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "efa" {
  count = local.create && var.enable_efa_security_group ? 1 : 0

  name        = "${var.name}-efa"
  description = "EFA self-referencing all-traffic SG for GPU<->GPU RDMA within the cluster placement group (ADR-0045)."
  vpc_id      = module.vpc[0].vpc_id

  tags = merge(local.base_tags, { "Name" = "${var.name}-efa" })
}

# All ingress from itself — EFA peers must reach every port on every other peer.
resource "aws_vpc_security_group_ingress_rule" "efa_self" {
  count = local.create && var.enable_efa_security_group ? 1 : 0

  security_group_id            = aws_security_group.efa[0].id
  referenced_security_group_id = aws_security_group.efa[0].id
  ip_protocol                  = "-1"
  description                  = "EFA all-traffic from peers in the same SG."

  tags = local.base_tags
}

# All egress to itself (EFA peers).
resource "aws_vpc_security_group_egress_rule" "efa_self" {
  count = local.create && var.enable_efa_security_group ? 1 : 0

  security_group_id            = aws_security_group.efa[0].id
  referenced_security_group_id = aws_security_group.efa[0].id
  ip_protocol                  = "-1"
  description                  = "EFA all-traffic to peers in the same SG."

  tags = local.base_tags
}
