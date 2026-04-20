# VPC Integration Test Fixture
# This configuration wraps the VPC module for Terratest integration tests.

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

module "vpc" {
  source = "../../../../terraform/modules/vpc"

  name         = var.vpc_name
  vpc_cidr     = var.vpc_cidr
  azs          = var.azs
  cluster_name = var.cluster_name
  enable_ha_nat = var.enable_ha_nat
  environment  = var.environment

  # Disable flow logs for integration tests to reduce cost
  enable_flow_log = var.enable_flow_log

  tags = var.tags
}
