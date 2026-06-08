# -----------------------------------------------------------------------------
# state-backend-dr — Cross-region DR for the Terraform state backend
# -----------------------------------------------------------------------------
# Adds:
#   1. An S3 replica bucket in `dr_region` (with the same hardening as the
#      primary).
#   2. An IAM role + policy in the primary region's account that S3 uses to
#      replicate objects from primary -> replica.
#   3. An `aws_s3_bucket_replication_configuration` on the primary bucket
#      pointing at the replica.
#   4. A DynamoDB Global-Tables-v2 replica of the lock table in `dr_region`.
#
# Caller is responsible for:
#   - Passing two aliased AWS providers: default (= primary_region) and `aws.dr`
#     (= dr_region).
#   - Setting `enable_dynamodb_streams = true` on the primary state-backend
#     module before applying this one. The aws_dynamodb_table_replica resource
#     fails apply otherwise.
#
# Closes #160 (cross-region DR for Terraform state).
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# DR replica bucket — created via the aliased `aws.dr` provider
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state_replica" {
  provider = aws.dr

  bucket        = "tfstate-${var.account_name}-${var.dr_region}"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name      = "tfstate-${var.account_name}-${var.dr_region}"
    Purpose   = "terraform-state-dr-replica"
    ManagedBy = "Terraform"
    Account   = var.account_name
    DROf      = "tfstate-${var.account_name}-${var.primary_region}"
  })
}

resource "aws_s3_bucket_versioning" "state_replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.state_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.state_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn_dr != null && var.kms_key_arn_dr != "" ? var.kms_key_arn_dr : null
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state_replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.state_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "state_replica" {
  provider = aws.dr

  bucket        = aws_s3_bucket.state_replica.id
  target_bucket = aws_s3_bucket.state_replica.id
  target_prefix = "access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "state_replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.state_replica.id

  rule {
    id     = "AbortIncompleteMultipartUpload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "NoncurrentVersionExpiration"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "state_replica" {
  provider = aws.dr

  bucket = aws_s3_bucket.state_replica.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state_replica.arn,
          "${aws_s3_bucket.state_replica.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyDeleteBucket"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:DeleteBucket"
        Resource  = aws_s3_bucket.state_replica.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM role used by S3 to replicate primary -> replica
# ---------------------------------------------------------------------------
resource "aws_iam_role" "replication" {
  name = "state-replication-${var.account_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name    = "state-replication-${var.account_name}"
    Purpose = "s3-cross-region-replication"
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "state-replication-${var.account_name}"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket",
          ]
          Resource = var.source_bucket_arn
        },
        {
          Effect = "Allow"
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging",
          ]
          Resource = "${var.source_bucket_arn}/*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags",
          ]
          Resource = "${aws_s3_bucket.state_replica.arn}/*"
        },
      ],
      # If the source bucket uses a CMK, the role needs kms:Decrypt against
      # that key. If the destination uses a CMK in the DR region, it needs
      # kms:Encrypt against that one. AWS-managed keys are handled
      # automatically and don't need explicit grants.
      var.source_kms_key_arn != null && var.source_kms_key_arn != "" ? [
        {
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = var.source_kms_key_arn
        }
      ] : [],
      var.kms_key_arn_dr != null && var.kms_key_arn_dr != "" ? [
        {
          Effect   = "Allow"
          Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
          Resource = var.kms_key_arn_dr
        }
      ] : [],
    )
  })
}

# ---------------------------------------------------------------------------
# Primary-bucket replication configuration
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_replication_configuration" "state" {
  # Replication can only be configured on a versioned bucket — make sure the
  # replica is in place first.
  depends_on = [aws_s3_bucket_versioning.state_replica]

  bucket = var.source_bucket_id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all-state"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.state_replica.arn
      storage_class = "STANDARD"

      # If a DR-region CMK is provided, ask S3 to re-encrypt with it on
      # arrival. Otherwise we let the destination bucket's default encryption
      # apply (`aws/s3`), which is also fine for state.
      dynamic "encryption_configuration" {
        for_each = var.kms_key_arn_dr != null && var.kms_key_arn_dr != "" ? [1] : []
        content {
          replica_kms_key_id = var.kms_key_arn_dr
        }
      }
    }

    # If the source side is encrypted with a CMK we have to opt-in to
    # replicating SSE-KMS objects.
    dynamic "source_selection_criteria" {
      for_each = var.source_kms_key_arn != null && var.source_kms_key_arn != "" ? [1] : []
      content {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# DynamoDB Global Tables v2 replica
# ---------------------------------------------------------------------------
# Promotes the existing lock table into a global table by attaching a replica
# in `dr_region`. Requires `stream_enabled = true` on the source table — gated
# at the state-backend module via `enable_dynamodb_streams`.
resource "aws_dynamodb_table_replica" "locks_dr" {
  provider = aws.dr

  global_table_arn = var.source_lock_table_arn

  # PITR mirrors the source's setting.
  point_in_time_recovery = true

  tags = merge(var.tags, {
    Name    = "terraform-locks-${var.account_name}-dr"
    Purpose = "terraform-locks-dr-replica"
    Account = var.account_name
    DROf    = var.source_lock_table_arn
  })
}
