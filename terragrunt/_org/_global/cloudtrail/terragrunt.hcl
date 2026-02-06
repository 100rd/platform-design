# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Organization Trail — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the organization-wide CloudTrail trail from the management account.
# Depends on Organization (for org ID) and KMS (for encryption key).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/cloudtrail"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.account_id
}

dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organization_id = "o-mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "kms" {
  config_path = "../../eu-west-1/kms"

  mock_outputs = {
    key_arns = {
      cloudtrail = "arn:aws:kms:eu-west-1:000000000000:key/mock-cloudtrail-key"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  trail_name      = "org-trail"
  organization_id = dependency.organization.outputs.organization_id
  kms_key_arn     = dependency.kms.outputs.key_arns["cloudtrail"]
  s3_bucket_name  = "cloudtrail-audit-logs-${local.account_id}"

  # Lifecycle: 90d Standard -> 1yr Glacier -> 7yr expire
  lifecycle_standard_days   = 90
  lifecycle_glacier_days    = 365
  lifecycle_expiration_days = 2555

  # Object Lock for tamper-proof retention (PCI-DSS Req 10.5)
  enable_object_lock         = true
  object_lock_retention_days = 365

  # CloudWatch Logs for real-time analysis
  cloudwatch_log_retention_days = 365

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
