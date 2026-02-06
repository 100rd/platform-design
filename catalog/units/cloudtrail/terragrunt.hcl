# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Organization Trail — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys an organization-wide CloudTrail trail with encrypted S3 storage,
# CloudWatch Logs integration, and data event logging for S3 and Lambda.
#
# PCI-DSS Requirements:
#   Req 10.1   — Audit trails linking access to individual users
#   Req 10.2   — Automated audit trails for all system components
#   Req 10.5   — Secure audit trails (KMS encryption, Object Lock)
#   Req 10.5.5 — File integrity monitoring (log file validation)
#   Req 10.7   — Retain audit logs >= 1 year (7 years configured)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/cloudtrail"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_id   = local.account_vars.locals.account_id
}

## NOTE: organization_id and kms_key_arn are REQUIRED inputs that must be provided
## by the consuming live config (e.g., terragrunt/_org/_global/cloudtrail/terragrunt.hcl)
## via dependencies on the organization and kms modules. They are intentionally omitted
## here because this catalog unit is a reusable template, not a standalone deployment.

inputs = {
  trail_name     = "org-trail"
  s3_bucket_name = "cloudtrail-audit-logs-${local.account_id}"

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
