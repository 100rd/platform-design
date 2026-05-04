# -----------------------------------------------------------------------------
# cloudtrail-org — Organization-wide CloudTrail
# -----------------------------------------------------------------------------
# Closes #161. This is a thin alias / consistency-naming wrapper around the
# existing `cloudtrail` module, which already produces an organization trail
# (is_organization_trail = true, is_multi_region_trail = true, log file
# validation, KMS CMK, S3 with Object Lock + lifecycle).
#
# Why a wrapper instead of renaming the underlying module?
#   - Issue #161 asks for a module named `cloudtrail-org` (mirroring the
#     source repo qbiq-ai/infra naming).
#   - The existing `cloudtrail` module already meets every acceptance
#     criterion in #161 and is referenced from terragrunt + tests.
#   - Renaming would churn a stable surface and require state moves on any
#     applied environments.
#
# This wrapper gives the canonical name without forcing a churn.
# Callers (new code) should reference `cloudtrail-org`. Existing
# `cloudtrail` callers continue to work; converging happens organically.
# -----------------------------------------------------------------------------

module "cloudtrail" {
  source = "../cloudtrail"

  trail_name      = var.trail_name
  organization_id = var.organization_id
  kms_key_arn     = var.kms_key_arn

  s3_bucket_name             = var.s3_bucket_name
  s3_key_prefix              = var.s3_key_prefix
  enable_object_lock         = var.enable_object_lock
  object_lock_retention_days = var.object_lock_retention_days

  lifecycle_standard_days   = var.lifecycle_standard_days
  lifecycle_glacier_days    = var.lifecycle_glacier_days
  lifecycle_expiration_days = var.lifecycle_expiration_days

  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days

  tags = var.tags
}
