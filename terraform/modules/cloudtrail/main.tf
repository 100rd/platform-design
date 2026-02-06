# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Organization Trail
# ---------------------------------------------------------------------------------------------------------------------
# Creates an organization-wide CloudTrail trail with:
#   - Multi-region coverage
#   - Log file integrity validation
#   - KMS CMK encryption (SSE-KMS)
#   - S3 bucket with Object Lock (WORM), versioning, lifecycle rules
#   - CloudWatch Logs integration for real-time analysis
#   - Management + data events (S3 and Lambda)
#
# PCI-DSS Requirements addressed:
#   Req 10.1   — Audit trails linking access to individual users
#   Req 10.2   — Automated audit trails for all system components
#   Req 10.3   — Record at minimum: user ID, event type, date/time, success/failure,
#                 origin, identity/name of affected data/resource
#   Req 10.5   — Secure audit trails so they cannot be altered
#   Req 10.5.3 — Promptly back up audit trail files (S3 cross-region replication optional)
#   Req 10.5.5 — Use file-integrity monitoring (log file validation)
#   Req 10.7   — Retain audit trail history for at least one year (we do 7 years)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket for CloudTrail Logs
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = var.s3_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name         = var.s3_bucket_name
    pci-dss-scope = "true"
    Purpose      = "cloudtrail-audit-logs"
  })
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "cloudtrail-lifecycle"
    status = "Enabled"

    transition {
      days          = var.lifecycle_standard_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.lifecycle_expiration_days
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.lifecycle_expiration_days
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket Policy — Allow CloudTrail to write logs
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_s3.json
}

data "aws_iam_policy_document" "cloudtrail_s3" {
  # CloudTrail ACL check
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${var.trail_name}"]
    }
  }

  # CloudTrail write — management account
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${var.trail_name}"]
    }
  }

  # CloudTrail write — organization member accounts
  statement {
    sid    = "AWSCloudTrailOrgWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.organization_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudtrail:${local.region}:${local.account_id}:trail/${var.trail_name}"]
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
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CloudWatch Log Group for Real-Time Analysis
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, {
    Name         = "/aws/cloudtrail/${var.trail_name}"
    pci-dss-scope = "true"
  })
}

# IAM role for CloudTrail to write to CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "${var.trail_name}-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudtrail.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name = "${var.trail_name}-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# CloudTrail Organization Trail
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudtrail" "org_trail" {
  name = var.trail_name

  # S3 configuration
  s3_bucket_name = aws_s3_bucket.cloudtrail.id
  s3_key_prefix  = var.s3_key_prefix

  # Organization trail — captures events from all accounts
  is_organization_trail = true

  # Multi-region — captures events in all AWS regions
  is_multi_region_trail = true

  # Log file validation — PCI-DSS Req 10.5.5
  enable_log_file_validation = true

  # KMS encryption — PCI-DSS Req 10.5
  kms_key_id = var.kms_key_arn

  # CloudWatch Logs integration
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # Include global service events (IAM, STS, etc.)
  include_global_service_events = true

  # Management events
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    # S3 data events
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${local.partition}:s3"]
    }

    # Lambda data events
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:${local.partition}:lambda"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
  ]

  tags = merge(var.tags, {
    Name         = var.trail_name
    pci-dss-scope = "true"
    Compliance   = "pci-dss-req-10"
  })
}
