# ---------------------------------------------------------------------------------------------------------------------
# Minimal Platform KMS Keys — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# KMS CMKs for the minimal-platform EKS stack.
#
# Key differences from the standard kms catalog unit:
#   - alias_prefix read from account.hcl (kms_alias_prefix) with backward-compatible
#     default of "staging-minimal-platform" so the existing staging stack is unchanged.
#     Sandbox sets kms_alias_prefix = "sandbox-minimal-platform" in account.hcl.
#   - allow_destroy = true — this is a test/validation stack that will be torn
#     down after the EKS+Cilium deployment pattern is validated. IaC-layer
#     deletion protection is intentionally disabled. AWS-native protection
#     (deletion_window_in_days = 30) and IAM still apply.
#     DO NOT propagate allow_destroy = true to platform/ or blockchain/ units.
#   - keys scoped to only what this stack consumes (eks-secrets + ebs). The
#     standard kms unit provisions 6 keys; this stack has no RDS, S3, Secrets
#     Manager, or CloudTrail units, so those keys are omitted.
#   - admin_arns / user_arns read from account.hcl (kms_admin_arns / kms_user_arns)
#     with backward-compatible default of OrganizationAccountAccessRole so the
#     existing staging stack continues to work without changes to staging/account.hcl.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/kms"
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

  # ---------------------------------------------------------------------------
  # KMS key policy principals — configurable per account.
  #
  # Accounts with AWS Organizations (staging, prod, dev) rely on the
  # OrganizationAccountAccessRole that is vended into every member account.
  # The personal sandbox account has no such role; instead account.hcl supplies
  # explicit IAM user ARNs via kms_admin_arns / kms_user_arns.
  #
  # Backward-compatible: if account.hcl does not define these locals (e.g. the
  # existing staging/account.hcl), the try() falls back to the org role default.
  # ---------------------------------------------------------------------------
  default_admin_arns = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]
  default_user_arns  = ["${local.iam_prefix}:role/OrganizationAccountAccessRole"]

  admin_arns = try(local.account_vars.locals.kms_admin_arns, local.default_admin_arns)
  user_arns  = try(local.account_vars.locals.kms_user_arns, local.default_user_arns)

  # ---------------------------------------------------------------------------
  # KMS alias prefix — scoped per account to prevent alias collisions.
  #
  # Default ("staging-minimal-platform") preserves existing staging behavior.
  # Sandbox overrides via kms_alias_prefix = "sandbox-minimal-platform" in
  # sandbox/account.hcl.
  # ---------------------------------------------------------------------------
  alias_prefix = try(local.account_vars.locals.kms_alias_prefix, "${local.environment}-minimal-platform")
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  environment = local.environment

  # Alias prefix scoped to this stack instance — prevents collision between
  # staging-minimal-platform and sandbox-minimal-platform in different accounts.
  alias_prefix = local.alias_prefix

  # Test stack: disable IaC-layer prevent_destroy so the stack can be torn down.
  # AWS-native 30-day deletion window and IAM protection still apply.
  allow_destroy = true

  # Only the 2 keys consumed by this stack:
  #   eks-secrets — EKS envelope encryption (cluster_encryption_config)
  #   ebs         — EKS node root volume encryption (block_device_mappings)
  # Keys for rds, s3-data, secrets-manager, and cloudtrail are omitted because
  # none of those units are deployed in this minimal stack.
  keys = {
    eks-secrets = {
      description = "PCI-DSS: Encryption key for minimal-platform EKS Kubernetes secrets envelope encryption"
      admin_arns  = local.admin_arns
      user_arns   = local.user_arns
    }

    ebs = {
      description = "PCI-DSS: Encryption key for minimal-platform EBS volumes attached to EKS nodes"
      admin_arns  = local.admin_arns
      user_arns   = local.user_arns
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
