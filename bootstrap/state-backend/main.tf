# -----------------------------------------------------------------------------
# Bootstrap: Terraform State Backend (per AWS account)
# -----------------------------------------------------------------------------
# Solves the chicken-and-egg problem: every Terragrunt unit in this repo wants
# to put its state in s3://tfstate-<account>-<region>, but that bucket doesn't
# exist on day one. This stack creates it.
#
# Critical: this stack runs with LOCAL state (no `backend` block). The
# resulting `terraform.tfstate` is intentionally short-lived — once the bucket
# is up, every other unit uses it for remote state. This bootstrap state file
# can be discarded (or kept as a record); re-running this stack on a populated
# account is a no-op courtesy of `prevent_destroy` + idempotent `aws_*`
# resources.
#
# How it's invoked: see `scripts/deploy-state-backends.sh` which:
#   1. Assumes OrganizationAccountAccessRole into the target account.
#   2. Copies this directory to a temp workspace.
#   3. Symlinks `terraform/modules/` so the module reference resolves.
#   4. Runs `terraform init && terraform plan|apply`.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }

  # NO backend block — local state is intentional during bootstrap.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Account    = var.account_name
      Region     = var.aws_region
      ManagedBy  = "terraform"
      Repository = "100rd/platform-design"
      Project    = "platform-design"
      Owner      = "platform-team"
      CostCenter = "platform"
      Purpose    = "tfstate-bootstrap"
    }
  }
}

module "state_backend" {
  source = "../../terraform/modules/state-backend"

  account_name = var.account_name
  aws_region   = var.aws_region
  kms_key_arn  = var.kms_key_arn

  tags = var.tags
}
