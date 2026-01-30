# -----------------------------------------------------------------------------
# Root Terragrunt Configuration
# -----------------------------------------------------------------------------
# Gruntwork-style root config for a multi-account, multi-region AWS platform.
# All child terragrunt.hcl files should include this via:
#
#   include "root" {
#     path = find_in_parent_folders()
#   }
#
# Hierarchy files expected in the directory tree:
#   account.hcl  - defines account_name, account_id
#   region.hcl   - defines aws_region
#   env.hcl      - defines environment
# -----------------------------------------------------------------------------

terragrunt_version_constraint = ">= 0.67.0"

# -----------------------------------------------------------------------------
# Locals: Read hierarchy config files
# -----------------------------------------------------------------------------
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.env_vars.locals.environment
}

# -----------------------------------------------------------------------------
# Remote State: S3 backend with DynamoDB locking
# -----------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = "tfstate-${local.account_name}-${local.aws_region}"
    key    = "${local.environment}/${path_relative_to_include()}/terraform.tfstate"
    region = local.aws_region

    encrypt        = true
    dynamodb_table = "terraform-locks-${local.account_name}"

    s3_bucket_tags = {
      Environment = local.environment
      ManagedBy   = "terragrunt"
      Account     = local.account_name
    }

    dynamodb_table_tags = {
      Environment = local.environment
      ManagedBy   = "terragrunt"
      Account     = local.account_name
    }
  }
}

# -----------------------------------------------------------------------------
# Generate: AWS Provider
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"

      assume_role {
        role_arn = "arn:aws:iam::${local.account_id}:role/TerragruntDeployRole"
      }

      default_tags {
        tags = {
          Environment = "${local.environment}"
          ManagedBy   = "terragrunt"
          Account     = "${local.account_name}"
          Region      = "${local.aws_region}"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Generate: Terraform and Provider Version Constraints
# -----------------------------------------------------------------------------
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    terraform {
      required_version = ">= 1.5.0"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.70"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Common Inputs: Passed to every module
# -----------------------------------------------------------------------------
inputs = {
  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Account     = local.account_name
    Region      = local.aws_region
  }
}
