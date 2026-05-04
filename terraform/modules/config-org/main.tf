# -----------------------------------------------------------------------------
# config-org — Organization-wide AWS Config wrapper
# -----------------------------------------------------------------------------
# Closes #162. Thin alias around the existing `aws-config` module which now
# supports organization aggregation and baseline conformance packs.
#
# Why a wrapper instead of renaming `aws-config`?
#   - Issue #162 asks for `modules/config-org` (mirroring qbiq-ai/infra
#     naming).
#   - The existing `aws-config` module already creates the recorder +
#     delivery channel + S3 + IAM role + CIS managed rules; renaming would
#     force state moves and break tests.
#   - The aggregator + conformance pack additions for #162 landed in the
#     existing module. This wrapper exposes them via the canonical name.
# -----------------------------------------------------------------------------

module "config" {
  source = "../aws-config"

  recorder_name = var.recorder_name

  s3_bucket_name              = var.s3_bucket_name
  s3_key_prefix               = var.s3_key_prefix
  snapshot_delivery_frequency = var.snapshot_delivery_frequency
  kms_key_arn                 = var.kms_key_arn

  lifecycle_glacier_days    = var.lifecycle_glacier_days
  lifecycle_expiration_days = var.lifecycle_expiration_days

  recording_all_resources       = var.recording_all_resources
  include_global_resource_types = var.include_global_resource_types

  # #162: org-wide aggregation + conformance pack
  enable_organization_aggregator            = var.enable_organization_aggregator
  organization_aggregator_name              = var.organization_aggregator_name
  enable_organization_conformance_pack      = var.enable_organization_conformance_pack
  organization_conformance_pack_name        = var.organization_conformance_pack_name
  baseline_conformance_pack_template_body   = var.baseline_conformance_pack_template_body
  baseline_conformance_pack_template_s3_uri = var.baseline_conformance_pack_template_s3_uri

  tags = var.tags
}
