# EKS Integration Test Fixture
# This configuration wraps the EKS module for Terratest integration tests.
# Note: Full EKS cluster creation takes 15-20 minutes. For CI, we use plan-only tests.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "test"
      ManagedBy   = "terratest"
      TestName    = var.test_name
    }
  }
}

# Create a VPC for EKS
module "vpc" {
  source = "../../../../terraform/modules/vpc"

  name            = "${var.cluster_name}-vpc"
  vpc_cidr        = var.vpc_cidr
  azs             = var.azs
  cluster_name    = var.cluster_name
  enable_ha_nat   = false
  enable_flow_log = false

  tags = var.tags
}

module "eks" {
  source = "../../../../terraform/modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # Minimal configuration for testing
  create_cluster_primary_security_group_tags = false
  create_cloudwatch_log_group                = false

  tags = var.tags
}
