# VPC Configuration for Simple EKS + Karpenter Environment
# This creates a dedicated VPC with public and private subnets across 3 AZs

include {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../terraform/modules/vpc"
}

locals {
  # Get environment name from parent
  env_vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  env      = local.env_vars.locals.env

  # Cluster name for Karpenter discovery tags
  cluster_name = "simple-eks-cluster"
}

inputs = {
  # VPC name
  name = "${local.env}-eks-vpc"

  # VPC CIDR block
  vpc_cidr = "10.0.0.0/16"

  # Cluster name for Karpenter subnet discovery
  cluster_name = local.cluster_name

  # Tags
  tags = {
    Environment = local.env
    ManagedBy   = "terragrunt"
    Project     = "eks-karpenter-demo"
    Purpose     = "Simple EKS with Karpenter and multi-arch support"
  }

  # Additional subnet tags (optional)
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}
