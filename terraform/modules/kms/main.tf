# ---------------------------------------------------------------------------------------------------------------------
# KMS Customer Managed Keys (CMKs)
# ---------------------------------------------------------------------------------------------------------------------
# Creates multiple KMS CMKs with aliases, automatic key rotation, and IAM key policies.
# Designed for PCI-DSS compliance: all keys enable rotation and include audit-friendly
# policies that grant CloudTrail logging access.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS Keys
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "this" {
  for_each = var.keys

  description             = each.value.description
  deletion_window_in_days = each.value.deletion_window_in_days
  key_usage               = each.value.key_usage
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.key_policy[each.key].json

  tags = merge(var.tags, {
    Name          = "${var.environment}-${each.key}"
    pci-dss-scope = "true"
    key-purpose   = each.key
    Environment   = var.environment
  })

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS Aliases
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_alias" "this" {
  for_each = var.keys

  name          = "alias/${var.environment}/${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

# ---------------------------------------------------------------------------------------------------------------------
# Key Policies
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "key_policy" {
  for_each = var.keys

  # Root account full access — required for IAM-based policy delegation
  statement {
    sid    = "RootAccountFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Key administrators — manage key lifecycle but not use it for crypto operations
  statement {
    sid    = "KeyAdministrators"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value.admin_arns
    }

    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]

    resources = ["*"]
  }

  # Key users — encrypt, decrypt, generate data keys
  statement {
    sid    = "KeyUsers"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value.user_arns
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]
  }

  # Grant creation for AWS services (EBS, RDS, S3, etc.)
  statement {
    sid    = "AllowServiceGrants"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value.user_arns
    }

    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]

    resources = ["*"]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # CloudTrail logging access
  statement {
    sid    = "AllowCloudTrailLogging"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}
