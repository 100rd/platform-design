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

    actions = ["s3:*"]
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

# ---------------------------------------------------------------------------------------------------------------------
# CIS AWS Foundations Benchmark v3.0 — Managed Config Rules
# ---------------------------------------------------------------------------------------------------------------------
# These rules detect but do not auto-remediate. They feed into the Config dashboard
# and SecurityHub findings. Add aws_config_remediation_configuration resources
# separately if auto-remediation is desired.
#
# CIS control references:
#   1.5  — Root account MFA
#   1.8–1.14 — IAM password policy
#   1.10 — MFA for IAM console users
#   1.14 — Access key rotation
#   3.1  — CloudTrail enabled
#   3.2  — CloudTrail log file validation
#   3.5  — CloudTrail encryption
#   3.7  — VPC flow logs
#   2.1.2 — S3 bucket public read prohibited
# ---------------------------------------------------------------------------------------------------------------------

# CIS 1.5 — Ensure MFA is enabled for the root account
resource "aws_config_config_rule" "root_mfa" {
  name        = "root-account-mfa-enabled"
  description = "CIS 1.5 - Ensure MFA is enabled for the root user account"

  source {
    owner             = "AWS"
    source_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 1.8–1.14 — IAM password policy
resource "aws_config_config_rule" "iam_password_policy" {
  name        = "iam-password-policy"
  description = "CIS 1.8-1.14 - Ensure IAM password policy meets CIS requirements (14-char min, 90-day rotation, 24 history)"

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols             = "true"
    RequireNumbers             = "true"
    MinimumPasswordLength      = "14"
    PasswordReusePrevention    = "24"
    MaxPasswordAge             = "90"
  })

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 1.10 — MFA for IAM console access
resource "aws_config_config_rule" "mfa_console_access" {
  name        = "mfa-enabled-for-iam-console-access"
  description = "CIS 1.10 - Ensure MFA is enabled for all IAM users that have console access"

  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 1.14 — Access keys rotated every 90 days
resource "aws_config_config_rule" "access_keys_rotated" {
  name        = "access-keys-rotated"
  description = "CIS 1.14 - Ensure access keys are rotated every 90 days or less"

  source {
    owner             = "AWS"
    source_identifier = "ACCESS_KEYS_ROTATED"
  }

  input_parameters = jsonencode({
    maxAccessKeyAge = "90"
  })

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 3.1 — CloudTrail enabled in all regions
resource "aws_config_config_rule" "cloudtrail_enabled" {
  name        = "cloud-trail-enabled"
  description = "CIS 3.1 - Ensure CloudTrail is enabled in all regions"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 3.2 — CloudTrail log file validation enabled
resource "aws_config_config_rule" "cloudtrail_log_validation" {
  name        = "cloud-trail-log-file-validation-enabled"
  description = "CIS 3.2 - Ensure CloudTrail log file validation is enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 3.5 — CloudTrail logs encrypted at rest with KMS
resource "aws_config_config_rule" "cloudtrail_encryption" {
  name        = "cloud-trail-encryption-enabled"
  description = "CIS 3.5 - Ensure CloudTrail logs are encrypted at rest using KMS CMKs"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 3.7 — VPC flow logs enabled in all VPCs
resource "aws_config_config_rule" "vpc_flow_logs" {
  name        = "vpc-flow-logs-enabled"
  description = "CIS 3.7 - Ensure VPC flow logging is enabled in all VPCs"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# CIS 1.14 (access key age) / CIS 2.1.2 — S3 bucket public read prohibited
resource "aws_config_config_rule" "s3_bucket_public_read" {
  name        = "s3-bucket-public-read-prohibited"
  description = "CIS 2.1.2 - Ensure S3 bucket policies do not allow public read access"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}

# ---------------------------------------------------------------------------------------------------------------------
# Org-wide aggregator (#162) — runs in the security/aggregator account
# ---------------------------------------------------------------------------------------------------------------------
# When `enable_organization_aggregator = true`, creates an
# `aws_config_configuration_aggregator` collecting findings from every
# member account in the organization. Typically applied in the security
# account after the org has delegated Config admin to it.
#
# The aggregator IAM role MUST have the
# AWSConfigRoleForOrganizations managed policy. We attach it explicitly
# below.
#
# Closes the #162 acceptance criterion: "Aggregator in security account".

resource "aws_iam_role" "config_aggregator" {
  count = var.enable_organization_aggregator ? 1 : 0

  name = "aws-config-org-aggregator"

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

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  count = var.enable_organization_aggregator ? 1 : 0

  role       = aws_iam_role.config_aggregator[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "organization" {
  count = var.enable_organization_aggregator ? 1 : 0

  name = var.organization_aggregator_name

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator[0].arn
  }

  tags = merge(var.tags, {
    Name    = var.organization_aggregator_name
    Purpose = "config-org-aggregator"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# Baseline conformance pack (#162) — applied at organization level when running in the management account
# ---------------------------------------------------------------------------------------------------------------------
# Conformance packs bundle Config rules + remediation actions. The simplest
# baseline is the AWS-managed "Operational Best Practices for AWS
# Foundational Security Best Practices" pack, applied org-wide.
#
# Set `baseline_conformance_pack_template_s3_uri` (or
# `baseline_conformance_pack_template_body`) to provision. Empty by default
# to keep this opt-in.
#
# Closes the #162 acceptance criterion: "Baseline conformance pack applied".

resource "aws_config_organization_conformance_pack" "baseline" {
  count = var.enable_organization_conformance_pack ? 1 : 0

  name = var.organization_conformance_pack_name

  # Template body OR S3 URI — exactly one must be set.
  template_body = var.baseline_conformance_pack_template_body != "" ? var.baseline_conformance_pack_template_body : null
  template_s3_uri = (
    var.baseline_conformance_pack_template_body == "" && var.baseline_conformance_pack_template_s3_uri != ""
    ? var.baseline_conformance_pack_template_s3_uri
    : null
  )

  delivery_s3_bucket     = aws_s3_bucket.config.id
  delivery_s3_key_prefix = "conformance-packs"

  depends_on = [
    aws_config_configuration_recorder_status.this,
    aws_config_configuration_aggregator.organization,
  ]
}
