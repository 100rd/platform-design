module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.5"

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

  # VPC Flow Logs — PCI-DSS Req 10 (logging & monitoring)
  enable_flow_log                                 = var.enable_flow_log
  flow_log_destination_type                       = var.flow_log_destination_type
  create_flow_log_cloudwatch_log_group            = var.create_flow_log_cloudwatch_log_group
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_max_aggregation_interval               = var.flow_log_max_aggregation_interval
  flow_log_traffic_type                           = var.flow_log_traffic_type

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
