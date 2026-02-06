# ---------------------------------------------------------------------------------------------------------------------
# Secrets Management Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions AWS Secrets Manager secrets using a custom Terraform module
# in the local modules directory. Secrets are encrypted with a KMS CMK and can be configured
# for automatic rotation via a Lambda function.
#
# PCI-DSS Controls:
#   Req 3.4   — Secrets encrypted at rest with KMS CMK (not default aws/secretsmanager key)
#   Req 3.6.4 — Automatic secret rotation (90-day cycle)
#
# Secrets are namespaced by environment, region, and service to avoid collisions and
# simplify IAM policy scoping.
#
# NOTE: Secret rotation requires a deployed Lambda function that implements the Secrets Manager
# rotation protocol. Set rotation_lambda_arn once the Lambda is available. Until then, secrets
# are created without rotation and must be rotated manually per PCI-DSS requirements.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/secrets"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: KMS (PCI-DSS Req 3.4 — CMK for secrets encryption)
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "secrets-manager" = "arn:aws:kms:eu-west-1:123456789012:key/mock-secrets-key-id"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  secrets = {
    "/${local.environment}/${local.aws_region}/platform/database/credentials" = {
      description     = "Platform database credentials"
      enable_rotation = true
    }
    "/${local.environment}/${local.aws_region}/platform/api/keys" = {
      description     = "Platform API keys"
      enable_rotation = false
    }
  }

  # KMS encryption for secrets at rest (PCI-DSS Req 3.4)
  kms_key_id = dependency.kms.outputs.key_arns["secrets-manager"]

  # Rotation configuration (PCI-DSS Req 3.6.4)
  # Set rotation_lambda_arn once the rotation Lambda is deployed.
  # Until then, rotation resources are not created (Lambda ARN is null).
  rotation_lambda_arn = null
  rotation_days       = 90

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
