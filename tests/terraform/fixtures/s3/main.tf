# S3 Integration Test Fixture
# This configuration wraps the S3 module for Terratest integration tests.

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

module "s3" {
  source = "../../../../terraform/modules/s3-app"

  bucket_name         = var.bucket_name
  versioning_enabled  = var.versioning_enabled
  force_destroy       = var.force_destroy
  create_iam_policies = var.create_iam_policies
  logging_bucket_name = var.logging_bucket_name
  lifecycle_rules     = var.lifecycle_rules

  tags = var.tags
}
