# -----------------------------------------------------------------------------
# Root Terragrunt Configuration
# -----------------------------------------------------------------------------
# Gruntwork Stacks-style root config for a multi-account, multi-region AWS
# platform. Units in the catalog include this via:
#
#   include "root" {
#     path = find_in_parent_folders("root.hcl")
#   }
#
# Hierarchy files expected in the directory tree:
#   account.hcl  - defines account_name, account_id, environment, sizing
#   region.hcl   - defines aws_region, region_short, azs
# -----------------------------------------------------------------------------

terragrunt_version_constraint = ">= 0.68.0"

# -----------------------------------------------------------------------------
# Locals: Read hierarchy config files
# -----------------------------------------------------------------------------
locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# -----------------------------------------------------------------------------
# Catalog: local infrastructure catalog
# -----------------------------------------------------------------------------
catalog {
  urls = ["${get_repo_root()}/catalog"]
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
      required_version = ">= 1.11.0"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.0"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Retry configuration for transient AWS errors
# -----------------------------------------------------------------------------
retry_max_attempts       = 3
retry_sleep_interval_sec = 5

retryable_errors = [
  "(?s).*Error creating.*",
  "(?s).*RequestError: send request failed.*",
  "(?s).*connection reset by peer.*",
]

# -----------------------------------------------------------------------------
# Common Inputs: Passed to every module
# -----------------------------------------------------------------------------
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  {
    tags = {
      Environment = local.environment
      ManagedBy   = "terragrunt"
      Account     = local.account_name
      Region      = local.aws_region
    }
  }
)
