# -----------------------------------------------------------------------------
# _envcommon: Centralized Logging module — shared inputs
# -----------------------------------------------------------------------------
# Aggregates org-wide logs (CloudTrail, VPC Flow, EKS audit/authenticator,
# Config snapshots) into the log-archive account's S3 bucket with KMS
# encryption and immutability via Object Lock.
#
# See issue #178 (EKS audit aggregation) and #182 (org-wide log-archive
# pattern) for the full design.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/centralized-logging"

  defaults = {
    # Lifecycle: 90d Standard -> 1yr Glacier -> 7yr expire (matches CloudTrail).
    lifecycle_standard_days   = 90
    lifecycle_glacier_days    = 365
    lifecycle_expiration_days = 2555

    # Object Lock for tamper-proof retention (PCI-DSS Req 10.5).
    enable_object_lock         = true
    object_lock_mode           = "GOVERNANCE"
    object_lock_retention_days = 365

    # Cross-account write permissions — the log-archive bucket is written to
    # by every member account's CloudTrail / Config / EKS audit pipeline.
    enable_cross_account_writes = true

    # Replication for DR (writes mirrored to a second region).
    enable_replication = true

    # SSE-KMS via customer-managed key.
    use_kms_encryption = true
  }
}

terraform {
  source = local.module_source
}

inputs = {
  lifecycle_standard_days     = local.defaults.lifecycle_standard_days
  lifecycle_glacier_days      = local.defaults.lifecycle_glacier_days
  lifecycle_expiration_days   = local.defaults.lifecycle_expiration_days
  enable_object_lock          = local.defaults.enable_object_lock
  object_lock_mode            = local.defaults.object_lock_mode
  object_lock_retention_days  = local.defaults.object_lock_retention_days
  enable_cross_account_writes = local.defaults.enable_cross_account_writes
  enable_replication          = local.defaults.enable_replication
  use_kms_encryption          = local.defaults.use_kms_encryption
}
