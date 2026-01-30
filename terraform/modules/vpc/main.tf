module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # NAT Gateway Configuration
  # Production: one NAT Gateway per AZ for HA (eliminates SPOF)
  # Dev/Staging: single NAT Gateway to reduce costs
  enable_nat_gateway     = true
  single_nat_gateway     = var.enable_ha_nat ? false : true
  one_nat_gateway_per_az = var.enable_ha_nat

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags for Karpenter subnet discovery
  private_subnet_tags = merge(
    var.private_subnet_tags,
    var.cluster_name != "" ? {
      "karpenter.sh/discovery" = var.cluster_name
    } : {}
  )

  # Tags for public subnets (for load balancers)
  public_subnet_tags = merge(
    var.public_subnet_tags,
    {
      "kubernetes.io/role/elb" = "1"
    }
  )

  tags = var.tags
}

