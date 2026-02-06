# ---------------------------------------------------------------------------------------------------------------------
# AWS Config — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys AWS Config configuration recorder and delivery channel with a dedicated
# S3 bucket for configuration snapshots and change history.
#
# PCI-DSS Requirements:
#   Req 1.1.1  — Formal process for testing/approving network connections (change tracking)
#   Req 2.4    — Maintain inventory of system components in scope (resource inventory)
#   Req 10.6   — Review logs and security events (configuration change timeline)
#   Req 11.5   — Change-detection mechanism (resource drift detection)
#
# Required inputs from consuming live config:
#   - s3_bucket_name (unique per account)
#   - kms_key_arn (from KMS dependency, optional)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/aws-config"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.account_id
}

inputs = {
  recorder_name               = "default"
  s3_bucket_name              = "aws-config-snapshots-${local.account_id}"
  snapshot_delivery_frequency = "TwentyFour_Hours"
  recording_all_resources     = true
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
