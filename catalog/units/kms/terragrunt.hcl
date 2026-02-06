# ---------------------------------------------------------------------------------------------------------------------
# KMS Customer Managed Keys — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions KMS CMKs for PCI-DSS compliance. Creates keys for
# EKS secrets encryption, RDS storage, S3 data-at-rest, Secrets Manager, EBS volumes,
# and CloudTrail log encryption.
#
# All keys enable automatic rotation and include policies granting CloudTrail logging
# access plus IAM role-based administration and usage.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/kms"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  # IAM ARN prefix for this account — used in key policies
  iam_prefix = "arn:aws:iam::${local.account_id}"

  # Default admin: the root-level admin role (adjust to match your IAM structure)
  default_admin_arns = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]

  # Default users: roles that need encrypt/decrypt access
  default_user_arns = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  environment = local.environment

  keys = {
    eks-secrets = {
      description = "PCI-DSS: Encryption key for EKS Kubernetes secrets envelope encryption"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    rds = {
      description = "PCI-DSS: Encryption key for RDS PostgreSQL storage encryption at rest"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    s3-data = {
      description = "PCI-DSS: Encryption key for S3 bucket data-at-rest encryption"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    secrets-manager = {
      description = "PCI-DSS: Encryption key for AWS Secrets Manager secrets"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    ebs = {
      description = "PCI-DSS: Encryption key for EBS volumes attached to EKS nodes"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    cloudtrail = {
      description = "PCI-DSS: Encryption key for CloudTrail audit log encryption"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
