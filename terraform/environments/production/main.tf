provider "aws" {
  region = "us-east-1"
}

variable "db_password" {
  description = "RDS master password. Pass via TF_VAR_db_password env var or -var flag. Never hardcode."
  type        = string
  sensitive   = true
}

locals {
  cluster_name = "dns-failover-prod"
  tags = {
    Environment = "production"
    Project     = "dns-failover"
    Terraform   = "true"
  }
}

# 1. VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false # High Availability for Prod
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required for Karpenter/EKS discovery (if we used them)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# 2. EKS Cluster
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = local.cluster_name
  cluster_version = "1.32"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  min_size     = 3
  max_size     = 6
  desired_size = 3
  instance_types = ["m5.large"]

  tags = local.tags
}

# 3. RDS Database
module "rds" {
  source = "../../modules/rds"

  identifier = "${local.cluster_name}-db"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Allow access from EKS nodes
  allowed_security_group_ids = [module.eks_cluster.node_security_group_id]

  db_name  = "dns_failover"
  username = "postgres"
  password = var.db_password

  instance_class    = "db.t3.small"
  allocated_storage = 20
  multi_az          = true
  environment       = "prod"

  tags = local.tags
}

# 4. Monitoring
module "monitoring" {
  source = "../../modules/monitoring"

  cluster_name      = module.eks_cluster.cluster_name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  
  enable_prometheus = true
  enable_grafana    = true

  tags = local.tags
}

# 5. Secrets
module "secrets" {
  source = "../../modules/secrets"

  tags = local.tags
}

# Outputs
output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "db_endpoint" {
  value = module.rds.db_instance_endpoint
}
