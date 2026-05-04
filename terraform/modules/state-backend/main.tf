# -----------------------------------------------------------------------------
# Terraform State Backend Module (TF-only — no CloudFormation)
# -----------------------------------------------------------------------------
# Creates an S3 bucket + DynamoDB lock table for Terraform/Terragrunt remote
# state. The names produced here MUST match the `remote_state` block in
# terragrunt/root.hcl:
#
#   bucket         = "tfstate-${local.account_name}-${local.aws_region}"
#   dynamodb_table = "terraform-locks-${local.account_name}"
#
# This module is consumed:
#   1. By the bootstrap stack at `bootstrap/state-backend/` for first-time
#      provisioning (per-account, before any Terragrunt unit can run).
#   2. Optionally by future Terragrunt units once a state backend already
#      exists in a different account/region (e.g. DR replica buckets).
#
# Hardening applied:
#   - Versioning ON
#   - Default encryption (aws:kms with bucket key)
#   - Block-all public access
#   - Server access logging to self
#   - Lifecycle: abort incomplete multipart uploads, expire noncurrent versions
#   - Bucket policy: deny non-TLS, deny DeleteBucket
#   - DynamoDB: PAY_PER_REQUEST, PITR, SSE
#   - lifecycle.prevent_destroy on both bucket and table
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# S3 Bucket — Terraform state storage
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket        = "tfstate-${var.account_name}-${var.aws_region}"
  force_destroy = false

  # Prevent accidental deletion of state bucket — must match the bucket
  # configured in terragrunt/root.hcl. Recreating it would orphan all state.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name      = "tfstate-${var.account_name}-${var.aws_region}"
    Purpose   = "terraform-state"
    ManagedBy = "Terraform"
    Account   = var.account_name
  })
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      # CIS 2.1.1 — encryption at rest. If a CMK is supplied it is used;
      # otherwise we fall through to the AWS-managed `aws/s3` key (still
      # `aws:kms`, just with a default master key).
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn != null && var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Self-logging: access logs land in the same bucket under `access-logs/`.
# Acceptable for a state-backend bucket (low traffic, audit trail preserved by
# versioning + bucket policy). For higher-isolation environments, point the
# target_bucket at a dedicated log-archive bucket instead.
resource "aws_s3_bucket_logging" "state" {
  bucket = aws_s3_bucket.state.id

  target_bucket = aws_s3_bucket.state.id
  target_prefix = "access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  # Filterless rules require an explicit empty filter under the AWS provider v6.
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

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*",
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
        Resource  = aws_s3_bucket.state.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# DynamoDB Table — Terraform state locking
# ---------------------------------------------------------------------------
# Name MUST match terragrunt/root.hcl:
#   dynamodb_table = "terraform-locks-${local.account_name}"
resource "aws_dynamodb_table" "locks" {
  name         = "terraform-locks-${var.account_name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn != null && var.kms_key_arn != "" ? var.kms_key_arn : null
  }

  # Prevent accidental deletion of lock table.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, {
    Name      = "terraform-locks-${var.account_name}"
    Purpose   = "terraform-locks"
    ManagedBy = "Terraform"
    Account   = var.account_name
  })
}
