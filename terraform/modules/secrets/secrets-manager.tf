# ---------------------------------------------------------------------------------------------------------------------
# Secrets Manager with Rotation Support (PCI-DSS Req 3.6.4)
# ---------------------------------------------------------------------------------------------------------------------
# PCI-DSS Req 3.6.4: Cryptographic key changes for keys that have reached the end of their cryptoperiod.
# Secret rotation ensures database credentials and API keys are cycled on a regular schedule.
#
# IMPORTANT: Rotation requires a Lambda function deployed separately. The rotation_lambda_arn
# variable must point to a Lambda that implements the Secrets Manager rotation protocol:
# https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-lambda-function.html
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name        = each.key
  description = each.value.description
  kms_key_id  = var.kms_key_id

  force_overwrite_replica_secret = each.value.replicate ? var.force_overwrite_replica : null

  # ---------------------------------------------------------------------------
  # Multi-Region Secret Replication (PCI-DSS Req 3.4)
  # ---------------------------------------------------------------------------
  # Replicates secrets to additional AWS regions for multi-cluster access.
  # Each replica is encrypted with the region-specific KMS CMK.
  # Only added when the secret has replicate = true and replica_regions is non-empty.
  # ---------------------------------------------------------------------------
  dynamic "replica" {
    for_each = each.value.replicate ? var.replica_regions : []

    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_id
    }
  }

  tags = var.tags
}

# We don't create secret versions here as they contain sensitive data.
# They should be populated manually or via a secure pipeline.

# ---------------------------------------------------------------------------------------------------------------------
# Secret Rotation (PCI-DSS Req 3.6.4)
# ---------------------------------------------------------------------------------------------------------------------
# Only enabled for secrets that have rotation configured AND when a rotation Lambda ARN is provided.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "rotation" {
  for_each = {
    for k, v in var.secrets : k => v
    if v.enable_rotation && var.rotation_lambda_arn != null
  }

  secret_id           = aws_secretsmanager_secret.secrets[each.key].id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}
