# ---------------------------------------------------------------------------------------------------------------------
# Centralized Logging — log-archive account
# ---------------------------------------------------------------------------------------------------------------------
# Aggregates org-wide audit trails (CloudTrail, Config snapshots, VPC Flow
# Logs, EKS audit/authenticator) into a single immutable S3 bucket in the
# log-archive account. Cross-region replicated to the DR region for
# audit-trail durability (PCI-DSS Req 10.5).
#
# Issue #182.
# ---------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Primary bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  # Object Lock requires bucket-level enablement at creation time.
  # Set object_lock_enabled = true here AND configure the lock rule below.
  object_lock_enabled = var.enable_object_lock

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "tier-and-expire"
    status = "Enabled"

    filter {} # apply to all objects

    transition {
      days          = var.lifecycle_standard_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_ia_days
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Expire incomplete multi-part uploads after 7 days.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# -----------------------------------------------------------------------------
# Bucket policy — grant scoped Put access to trusted log-source roles in each
# member account, plus the AWS service principals that write directly
# (cloudtrail.amazonaws.com, config.amazonaws.com, etc.).
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "bucket" {
  # Deny non-TLS access (AWS-Foundational-Best-Practices.S3.5).
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Cross-account writes per log-source prefix.
  dynamic "statement" {
    for_each = var.trusted_writer_account_ids
    content {
      sid     = "AllowOrgAccount${replace(statement.value, "-", "")}"
      effect  = "Allow"
      actions = ["s3:PutObject", "s3:PutObjectAcl"]
      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${statement.value}:root"]
      }
      resources = [for k, v in var.log_source_prefixes : "${aws_s3_bucket.this.arn}/${v}/AWSLogs/${statement.value}/*"]
      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }
    }
  }

  # CloudTrail service principal needs a top-level GetBucketAcl too.
  statement {
    sid     = "AllowCloudTrailGetBucketAcl"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid     = "AllowCloudTrailPutObject"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.this.arn}/${var.log_source_prefixes["cloudtrail"]}/AWSLogs/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # Config service principal — same pattern.
  statement {
    sid     = "AllowConfigPutObject"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.this.arn}/${var.log_source_prefixes["config"]}/AWSLogs/*"]
  }

  statement {
    sid     = "AllowConfigGetBucketAcl"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = [aws_s3_bucket.this.arn]
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

# -----------------------------------------------------------------------------
# DR region — replicated bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "dr" {
  count    = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  provider = aws.dr

  bucket              = "${var.bucket_name}-dr"
  object_lock_enabled = var.enable_object_lock

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "dr" {
  count    = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.dr[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "dr" {
  count    = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  provider = aws.dr

  bucket                  = aws_s3_bucket.dr[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  count    = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  provider = aws.dr

  bucket = aws_s3_bucket.dr[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.dr_kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# -----------------------------------------------------------------------------
# Replication role + rule
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "replication_assume" {
  count = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count              = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  name               = "${var.bucket_name}-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "replication" {
  count = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0

  statement {
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.dr[0].arn}/*"]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }

  statement {
    actions   = ["kms:Encrypt"]
    resources = [var.dr_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "replication" {
  count  = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0
  name   = "${var.bucket_name}-replication"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication && var.dr_kms_key_arn != "" ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.this, aws_s3_bucket_versioning.dr]
  bucket     = aws_s3_bucket.this.id
  role       = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-everything"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.dr[0].arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = var.dr_kms_key_arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}
