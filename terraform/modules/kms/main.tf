# ---------------------------------------------------------------------------------------------------------------------
# KMS Customer Managed Keys (CMKs)
# ---------------------------------------------------------------------------------------------------------------------
# Creates multiple KMS CMKs with aliases, automatic key rotation, and IAM key policies.
# Designed for PCI-DSS compliance: all keys enable rotation and include audit-friendly
# policies that grant CloudTrail logging access.
#
# IMPLEMENTATION NOTE — conditional prevent_destroy:
#   Terraform lifecycle.prevent_destroy is a literal-only meta-argument; it does not
#   accept input variables or expressions (even in Terraform 1.14). We use a dual-
#   resource pattern to express the conditional:
#
#     aws_kms_key.this_protected   — created when allow_destroy = false (default)
#                                    lifecycle { prevent_destroy = true }
#     aws_kms_key.this_destroyable — created when allow_destroy = true (test stacks)
#                                    no lifecycle block
#
#   The two for_each sets are mutually exclusive (one is always empty). A local
#   "all_keys" merges both maps, so downstream resources (aliases, outputs) work
#   identically regardless of which variant is active. Existing callers that do NOT
#   pass allow_destroy (default = false) continue to receive protect_destroy = true,
#   byte-identical to pre-round-1 behavior.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Merge the two mutually-exclusive resource maps into a single addressable map.
  # Exactly one of the two maps will be non-empty at any given time.
  all_keys = merge(aws_kms_key.this_protected, aws_kms_key.this_destroyable)
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS Keys — protected variant (allow_destroy = false, default)
# ---------------------------------------------------------------------------------------------------------------------
# This resource is created for all standard callers. Deletion protection at the
# IaC layer prevents accidental `terraform destroy` of shared CMKs.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "this_protected" {
  for_each = var.allow_destroy ? {} : var.keys

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
# KMS Keys — destroyable variant (allow_destroy = true, test/minimal stacks only)
# ---------------------------------------------------------------------------------------------------------------------
# This resource is created ONLY when allow_destroy = true. No lifecycle guard is
# applied, allowing the stack to be torn down cleanly in CI/CD test environments.
# AWS-native protection (deletion_window_in_days = 30) and IAM still apply.
# DO NOT set allow_destroy = true in platform/ or blockchain/ catalog units.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_key" "this_destroyable" {
  for_each = var.allow_destroy ? var.keys : {}

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
}

# ---------------------------------------------------------------------------------------------------------------------
# KMS Aliases
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_kms_alias" "this" {
  for_each = local.all_keys

  name          = "alias/${var.alias_prefix != "" ? var.alias_prefix : var.environment}/${each.key}"
  target_key_id = local.all_keys[each.key].key_id
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
