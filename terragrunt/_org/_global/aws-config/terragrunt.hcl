# ---------------------------------------------------------------------------------------------------------------------
# AWS Config — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Deploys AWS Config configuration recorder with S3-backed delivery channel.
# Records all resource types including global resources (IAM).
# Depends on KMS for S3 bucket encryption.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/aws-config"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.account_id
}

dependency "kms" {
  config_path = "../../eu-west-1/kms"

  mock_outputs = {
    key_arns = {
      s3-data = "arn:aws:kms:eu-west-1:000000000000:key/mock-s3-key"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  recorder_name                 = "default"
  s3_bucket_name                = "aws-config-snapshots-${local.account_id}"
  s3_key_prefix                 = "config"
  kms_key_arn                   = dependency.kms.outputs.key_arns["s3-data"]
  snapshot_delivery_frequency   = "TwentyFour_Hours"
  recording_all_resources       = true
  include_global_resource_types = true

  # Lifecycle: 1yr Glacier -> 7yr expire
  lifecycle_glacier_days    = 365
  lifecycle_expiration_days = 2555

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
