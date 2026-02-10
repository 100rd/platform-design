# ---------------------------------------------------------------------------------------------------------------------
# AWS Config Configuration Recorder + Delivery Channel
# ---------------------------------------------------------------------------------------------------------------------
# Records all resource configurations and changes for compliance auditing.
# Creates a dedicated S3 bucket with encryption, versioning, and lifecycle rules.
#
# PCI-DSS Requirements addressed:
#   Req 1.1.1  — Formal process for testing/approving network connections (Config tracks changes)
#   Req 2.4    — Maintain an inventory of system components in scope (Config resource inventory)
#   Req 10.6   — Review logs and security events (Config change timeline)
#   Req 11.5   — Change-detection mechanism (Config detects resource drift)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  use_kms    = var.kms_key_arn != ""
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket for Config Snapshots
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "config" {
  bucket        = var.s3_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name          = var.s3_bucket_name
    pci-dss-scope = "true"
    Purpose       = "aws-config-snapshots"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.use_kms
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "config-lifecycle"
    status = "Enabled"

    transition {
      days          = var.lifecycle_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_expiration_days
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket Policy — Allow AWS Config to write
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_s3.json
}

data "aws_iam_policy_document" "config_s3" {
  # Config ACL check
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Config bucket existence check
  statement {
    sid    = "AWSConfigBucketExistenceCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Config write
  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/${var.s3_key_prefix}/AWSLogs/${local.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Enforce TLS
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.config.arn,
      "${aws_s3_bucket.config.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Role for AWS Config
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "config" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "aws-config-s3-delivery"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetBucketAcl",
      ]
      Resource = [
        aws_s3_bucket.config.arn,
        "${aws_s3_bucket.config.arn}/*",
      ]
      Condition = {
        StringLike = {
          "s3:x-amz-acl" = "bucket-owner-full-control"
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Configuration Recorder
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "this" {
  name     = var.recorder_name
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = var.recording_all_resources
    include_global_resource_types = var.include_global_resource_types
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Delivery Channel
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_config_delivery_channel" "this" {
  name           = var.recorder_name
  s3_bucket_name = aws_s3_bucket.config.id
  s3_key_prefix  = var.s3_key_prefix

  snapshot_delivery_properties {
    delivery_frequency = var.snapshot_delivery_frequency
  }

  depends_on = [aws_config_configuration_recorder.this]
}

# ---------------------------------------------------------------------------------------------------------------------
# Enable Recorder
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
