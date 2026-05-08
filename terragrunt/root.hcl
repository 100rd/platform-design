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
#   account.hcl   - defines account_name, account_id, environment, sizing
#   region.hcl    - defines aws_region, region_short, azs
#
# Sourced helper files (sibling to this file):
#   versions.hcl  - tool + provider version pins
#   common.hcl    - shared locals (project metadata, tag conventions, regions)
#
# Sandbox mode (account_name == "sandbox"):
#   - Uses pre-existing bucket "opsfleet-terraform-state-<account_id>"
#   - Bucket physically lives in eu-central-1; state_bucket_region in account.hcl
#     pins the backend region so eu-west-1 deployments still reach the bucket.
#   - S3 native locking (use_lockfile = true, TF >= 1.10) — no DynamoDB needed
#   - Provider block omits assume_role (IAM user direct access, no deploy role)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Sourced configs
# -----------------------------------------------------------------------------
locals {
  versions     = read_terragrunt_config(find_in_parent_folders("versions.hcl"))
  common       = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  # Cost allocation and audit tracing tags — read from account.hcl with
  # safe fallbacks to common.hcl defaults.
  owner       = try(local.account_vars.locals.owner, local.common.locals.default_owner)
  cost_center = try(local.account_vars.locals.cost_center, local.common.locals.default_cost_center)

  # Pinned provider version (single source of truth: versions.hcl).
  aws_provider_version = local.versions.locals.provider_versions.aws

  # Sandbox flag — drives backend bucket, locking strategy, and assume_role.
  # All non-sandbox environments are unaffected: identical behavior as before.
  is_sandbox = local.account_name == "sandbox"

  # State bucket region — may differ from deployment region for sandbox.
  # The sandbox S3 bucket "opsfleet-terraform-state-007027391583" was created
  # in eu-central-1 and cannot be relocated. account.hcl sets state_bucket_region
  # = "eu-central-1" so deployments to eu-west-1 still point at the right bucket.
  # For all non-sandbox accounts the state bucket is per-region so this falls
  # back to aws_region with no change in behavior.
  state_bucket_region = try(local.account_vars.locals.state_bucket_region, local.aws_region)
}

# -----------------------------------------------------------------------------
# Terragrunt version pin (single source of truth: versions.hcl)
# -----------------------------------------------------------------------------
terragrunt_version_constraint = local.versions.locals.terragrunt_version_constraint

# -----------------------------------------------------------------------------
# Catalog: local infrastructure catalog
# -----------------------------------------------------------------------------
catalog {
  urls = ["${get_repo_root()}/catalog"]
}

# -----------------------------------------------------------------------------
# Remote State: S3 backend with per-account locking strategy
#
# Non-sandbox (staging / prod / dev / …):
#   bucket         = tfstate-<account_name>-<region>
#   dynamodb_table = terraform-locks-<account_name>
#   use_lockfile   = false  (DynamoDB locking, existing behavior — unchanged)
#
# Sandbox (account_name == "sandbox"):
#   bucket       = opsfleet-terraform-state-<account_id>  (pre-existing)
#   region       = state_bucket_region (eu-central-1 — bucket's home region)
#   use_lockfile = true  (S3 native locking, TF >= 1.10 — we run 1.14.8)
#   No DynamoDB table required or created.
#
# Type-consistency note (Terragrunt v0.68):
#   Both branches of the is_sandbox ternary inside merge() must have identical
#   key shapes. Both branches declare all keys; the unused side uses null so
#   Terragrunt omits it from the rendered backend config while satisfying the
#   type checker. dynamodb_table_tags is null in the sandbox branch.
# -----------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = merge(
    {
      bucket  = local.is_sandbox ? "opsfleet-terraform-state-${local.account_id}" : "tfstate-${local.account_name}-${local.aws_region}"
      key     = "${local.environment}/${path_relative_to_include()}/terraform.tfstate"
      region  = local.state_bucket_region
      encrypt = true

      s3_bucket_tags = {
        Environment = local.environment
        ManagedBy   = local.common.locals.managed_by_tag_value
        Account     = local.account_name
      }
    },
    local.is_sandbox
    ? {
      # S3 native locking — no DynamoDB table needed in sandbox account (TF >= 1.10)
      use_lockfile        = true
      dynamodb_table      = null
      dynamodb_table_tags = null
    }
    : {
      use_lockfile   = false
      dynamodb_table = "terraform-locks-${local.account_name}"

      dynamodb_table_tags = {
        Environment = local.environment
        ManagedBy   = local.common.locals.managed_by_tag_value
        Account     = local.account_name
      }
    }
  )
}

# -----------------------------------------------------------------------------
# Generate: AWS Provider
#
# Non-sandbox: assumes TerragruntDeployRole in the target account. This is the
#   org-vended cross-account role used by CI/CD pipelines.
#
# Sandbox: no assume_role block — IAM user "igor" (007027391583) authenticates
#   directly via AWS_PROFILE or environment credentials. OrganizationAccountAccessRole
#   does not exist in this personal account.
#
# Note: HCL does not support ternary expressions with heredoc branches.
# The assume_role block is rendered conditionally by including an empty string
# when is_sandbox = true, or the full block when is_sandbox = false.
# -----------------------------------------------------------------------------
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"
      %{if !local.is_sandbox}

      assume_role {
        role_arn = "arn:aws:iam::${local.account_id}:role/TerragruntDeployRole"
      }
      %{endif}

      default_tags {
        tags = {
          Environment    = "${local.environment}"
          ManagedBy      = "${local.common.locals.managed_by_tag_value}"
          Account        = "${local.account_name}"
          Region         = "${local.aws_region}"
          Owner          = "${local.owner}"
          CostCenter     = "${local.cost_center}"
          TerragruntPath = "${path_relative_to_include()}"
          Repository     = "${local.common.locals.repository}"
          Project        = "${local.common.locals.project_name}"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Generate: Terraform and Provider Version Constraints
# Pinned via versions.hcl
# -----------------------------------------------------------------------------
generate "versions" {
  path      = "versions_override.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<-EOF
    terraform {
      required_version = "${local.versions.locals.terraform_version_constraint}"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "${local.aws_provider_version}"
        }
      }
    }
  EOF
}

# -----------------------------------------------------------------------------
# Common Inputs: Passed to every module
# -----------------------------------------------------------------------------
inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  {
    tags = {
      Environment    = local.environment
      ManagedBy      = local.common.locals.managed_by_tag_value
      Account        = local.account_name
      Region         = local.aws_region
      Owner          = local.owner
      CostCenter     = local.cost_center
      TerragruntPath = path_relative_to_include()
      Repository     = local.common.locals.repository
      Project        = local.common.locals.project_name
    }
  }
)
