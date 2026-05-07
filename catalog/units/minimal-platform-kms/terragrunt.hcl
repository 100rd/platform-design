# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform KMS Keys — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# KMS CMKs for the minimal-platform EKS stack.
#
# Key difference from the standard kms catalog unit:
#   - alias_prefix = "staging-minimal-platform" prevents alias collision with the
#     standard platform stack's alias/staging/<key> aliases in the same account.
#     Produces aliases of the form alias/staging-minimal-platform/<key>.
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

  # IAM ARN prefix for this account
  iam_prefix = "arn:aws:iam::${local.account_id}"

  default_admin_arns = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]
  default_user_arns  = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  environment = local.environment

  # Decision 4 (alias collision prevention): scoped prefix so aliases do not collide
  # with the standard platform stack's alias/staging/<key> in the same AWS account.
  alias_prefix = "staging-minimal-platform"

  keys = {
    eks-secrets = {
      description = "PCI-DSS: Encryption key for minimal-platform EKS Kubernetes secrets envelope encryption"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    rds = {
      description = "PCI-DSS: Encryption key for minimal-platform RDS PostgreSQL storage encryption at rest"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    s3-data = {
      description = "PCI-DSS: Encryption key for minimal-platform S3 bucket data-at-rest encryption"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    secrets-manager = {
      description = "PCI-DSS: Encryption key for minimal-platform AWS Secrets Manager secrets"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    ebs = {
      description = "PCI-DSS: Encryption key for minimal-platform EBS volumes attached to EKS nodes"
      admin_arns  = local.default_admin_arns
      user_arns   = local.default_user_arns
    }

    cloudtrail = {
      description = "PCI-DSS: Encryption key for minimal-platform CloudTrail audit log encryption"
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
