# -----------------------------------------------------------------------------
# _envcommon: KMS module — shared inputs and key inventory
# -----------------------------------------------------------------------------
# This unit owns the per-region KMS key inventory. Other units (cloudtrail,
# aws-config, eks secrets, s3) read from `key_arns["<purpose>"]` via a
# `dependency "kms"` block.
# -----------------------------------------------------------------------------

locals {
  module_source = "${get_repo_root()}/project/platform-design/terraform/modules/kms"

  # Canonical key inventory — extend (don't shrink) when new use-cases land.
  # Each key gets:
  #   - its own CMK with rotation enabled
  #   - a dedicated alias `alias/${env}-<purpose>`
  defaults = {
    keys = {
      cloudtrail  = { description = "CloudTrail org trail encryption" }
      aws-config  = { description = "AWS Config snapshot encryption" }
      s3-data     = { description = "S3 data buckets encryption" }
      eks-secrets = { description = "EKS secrets envelope encryption" }
      ebs         = { description = "EBS volumes default encryption" }
      rds         = { description = "RDS storage encryption" }
      sns         = { description = "SNS topics encryption" }
      sqs         = { description = "SQS queues encryption" }
      logs        = { description = "CloudWatch Logs encryption" }
      backup      = { description = "AWS Backup vault encryption" }
    }

    enable_key_rotation     = true
    deletion_window_in_days = 30
  }
}

terraform {
  source = local.module_source
}

inputs = {
  keys                    = local.defaults.keys
  enable_key_rotation     = local.defaults.enable_key_rotation
  deletion_window_in_days = local.defaults.deletion_window_in_days
}
