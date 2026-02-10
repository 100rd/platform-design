resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 access logging - PCI-DSS Req 10.1 (audit trails for all access)
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_bucket_name != "" ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_bucket_name
  target_prefix = "s3-access-logs/${var.bucket_name}/"
}

# ---------------------------------------------------------------------------------------------------------------------
# Bucket Policy — Enforce TLS (PCI-DSS Req 4.1)
# ---------------------------------------------------------------------------------------------------------------------
# Denies any S3 operation over an insecure (non-TLS) transport. This ensures all data
# in transit to/from the bucket is encrypted, satisfying PCI-DSS Requirement 4.1.
# Pattern sourced from the CloudTrail module's DenyInsecureTransport statement.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = lookup(rule.value, "prefix", "")
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transitions", [])
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration_days", null) != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }
    }
  }
}

# IAM policy for IRSA access
data "aws_iam_policy_document" "readwrite" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "readonly" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "readwrite" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.bucket_name}-s3-readwrite"
  policy = data.aws_iam_policy_document.readwrite.json

  tags = var.tags
}

resource "aws_iam_policy" "readonly" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.bucket_name}-s3-readonly"
  policy = data.aws_iam_policy_document.readonly.json

  tags = var.tags
}
