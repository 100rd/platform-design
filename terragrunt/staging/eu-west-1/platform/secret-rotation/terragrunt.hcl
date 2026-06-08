# ---------------------------------------------------------------------------------------------------------------------
# Secret Rotation — Staging, eu-west-1 (ADR-0031)
# ---------------------------------------------------------------------------------------------------------------------
# Automated rotation of a DB/API credential via a Secrets Manager rotation Lambda,
# scoped least-privilege IAM, KMS encryption, and VPC config so the Lambda can reach
# the private RDS instance. Replaces static long-lived secrets.
#
# This unit owns ONE rotated credential (the app DB primary credential). Add further
# units (or extend modules/secrets with this unit's rotation_lambda_arn output) for
# additional secrets.
#
# The bundled Lambda is a NON-FUNCTIONAL placeholder — set `lambda_package_path` to an
# AWS-provided RDS rotation template (single-user / alternating-user) before enabling
# rotation against a live database.
#
# Epic #252.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/secret-rotation"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
}

# KMS CMK for the secret + the rotator's scoped kms:Decrypt/GenerateDataKey grant.
# In live use this is the `rds` (or a dedicated secrets) key from the regional kms
# unit; mocked here so plan/validate succeed without applied state.
dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      rds = "arn:aws:kms:eu-west-1:222222222222:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# Private subnets + DB security group so the rotation Lambda can reach the RDS
# instance. In live use these come from the network/RDS units; placeholders here.
dependency "network" {
  config_path = "../connectivity/vpc"

  mock_outputs = {
    private_subnets   = ["subnet-0mock0a", "subnet-0mock0b", "subnet-0mock0c"]
    database_subnets  = ["subnet-0db0mock0a", "subnet-0db0mock0b"]
    rds_access_sg_ids = ["sg-0mockrotator00"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name               = "${local.environment}/app-db/credentials"
  secret_description = "App database primary credentials (rotated) — ${local.environment} ${local.aws_region}"
  kms_key_arn        = dependency.kms.outputs.key_arns["rds"]

  # 30-day cadence (PCI-DSS Req 3.6.4 <= 90). Switch to a schedule_expression for a
  # fixed maintenance window by setting rotation_after_days = null.
  rotation_after_days = 30

  # The rotation Lambda runs in the DB subnets and uses the DB-access SG so it can
  # reach the private RDS instance. Replace mocks with the real network outputs.
  vpc_subnet_ids         = try(dependency.network.outputs.database_subnets, [])
  vpc_security_group_ids = try(dependency.network.outputs.rds_access_sg_ids, [])

  # Placeholder handler is shipped by default. Before enabling rotation against a
  # live DB, point this at an AWS RDS rotation template package:
  # lambda_package_path = "${get_repo_root()}/.../rds-single-user-rotation.zip"

  log_retention_days = 365

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "secret-rotation"
    ADR         = "0031"
  }
}
