locals {
  azs = var.azs != null && length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)

  subnet_prefixes = cidrsubnets(var.vpc_cidr, 8, 6)
  public_subnets  = [for i in range(3) : local.subnet_prefixes[i]]
  private_subnets = [for i in range(3, 6) : local.subnet_prefixes[i]]
}
