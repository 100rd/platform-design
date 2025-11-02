module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
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

