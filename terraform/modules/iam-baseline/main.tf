# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline — Account Password Policy & MFA Documentation
# ---------------------------------------------------------------------------------------------------------------------
# Enforces a PCI-DSS-compliant password policy across the AWS account.
#
# PCI-DSS Requirements addressed:
#   Req 8.2.3 — Minimum password length (7 required, 14 implemented for defense in depth)
#   Req 8.2.4 — Password change at least every 90 days
#   Req 8.2.5 — No reuse of last 4 passwords (24 implemented for defense in depth)
#   Req 8.3.6 — First-time / reset passwords must be unique and changed immediately
#
# CIS AWS Foundations Benchmark:
#   CIS 1.8-1.14 — IAM password policy
#   CIS 1.20     — IAM Access Analyzer enabled
#   CIS 2.1.5    — S3 account-level public access block
#   CIS 2.2.1    — EBS encryption by default
#
# MFA Enforcement (Req 8.3):
#   IAM Identity Center MFA is configured via the console — see notes below.
#   For IAM users (break-glass only), MFA is enforced via the SCP deny-root-account
#   policy and the conditional MFA policy in this module.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "pci_dss" {
  minimum_password_length        = var.minimum_password_length
  require_lowercase_characters   = var.require_lowercase_characters
  require_uppercase_characters   = var.require_uppercase_characters
  require_numbers                = var.require_numbers
  require_symbols                = var.require_symbols
  max_password_age               = var.max_password_age
  password_reuse_prevention      = var.password_reuse_prevention
  allow_users_to_change_password = var.allow_users_to_change_password
  hard_expiry                    = var.hard_expiry
}

# ---------------------------------------------------------------------------------------------------------------------
# MFA Enforcement for IAM Users (Break-Glass Accounts)
# ---------------------------------------------------------------------------------------------------------------------
# This policy denies all actions except IAM self-service when MFA is not present.
# Attach to any IAM group containing break-glass / emergency-access users.
# Primary human access should go through IAM Identity Center (SSO) instead.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_policy" "enforce_mfa" {
  name        = "${var.name_prefix}EnforceMFA"
  description = "Denies all actions except IAM self-service when MFA is not present (PCI-DSS Req 8.3)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowViewAccountInfo"
        Effect = "Allow"
        Action = [
          "iam:GetAccountPasswordPolicy",
          "iam:ListVirtualMFADevices",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowManageOwnMFA"
        Effect = "Allow"
        Action = [
          "iam:CreateVirtualMFADevice",
          "iam:DeleteVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:ListMFADevices",
          "iam:ResyncMFADevice",
        ]
        Resource = [
          "arn:aws:iam::*:mfa/$${aws:username}",
          "arn:aws:iam::*:user/$${aws:username}",
        ]
      },
      {
        Sid    = "AllowManageOwnPassword"
        Effect = "Allow"
        Action = [
          "iam:ChangePassword",
          "iam:GetUser",
        ]
        Resource = "arn:aws:iam::*:user/$${aws:username}"
      },
      {
        Sid    = "DenyAllExceptListedIfNoMFA"
        Effect = "Deny"
        NotAction = [
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:GetUser",
          "iam:ChangePassword",
          "iam:GetAccountPasswordPolicy",
          "iam:ListMFADevices",
          "iam:ListVirtualMFADevices",
          "iam:ResyncMFADevice",
          "sts:GetSessionToken",
        ]
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
        }
      },
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Access Analyzer — CIS 1.20
# ---------------------------------------------------------------------------------------------------------------------
# Deploy ORGANIZATION type in the management account, ACCOUNT in all others.
# Controlled via var.analyzer_type.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_accessanalyzer_analyzer" "org" {
  count = var.analyzer_type == "ORGANIZATION" ? 1 : 0

  analyzer_name = "${var.name_prefix}org-access-analyzer"
  type          = "ORGANIZATION"

  tags = var.tags
}

resource "aws_accessanalyzer_analyzer" "account" {
  count = var.analyzer_type == "ACCOUNT" ? 1 : 0

  analyzer_name = "${var.name_prefix}account-access-analyzer"
  type          = "ACCOUNT"

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Account-Level Public Access Block — CIS 2.1.5
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------------------------------------------------
# EBS Encryption by Default — CIS 2.2.1
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# Optionally set a specific KMS key for default EBS encryption
resource "aws_ebs_default_kms_key" "this" {
  count = var.ebs_kms_key_arn != "" ? 1 : 0

  key_arn = var.ebs_kms_key_arn
}

# ---------------------------------------------------------------------------------------------------------------------
# Account alias — #165
# ---------------------------------------------------------------------------------------------------------------------
# Sets the AWS account alias, which appears in the IAM sign-in URL and in
# CloudTrail / billing reports. Helps humans identify which account they're
# acting in. CIS 1.1 / #165 acceptance criterion.

resource "aws_iam_account_alias" "this" {
  count = var.account_alias != "" ? 1 : 0

  account_alias = var.account_alias
}

# ---------------------------------------------------------------------------------------------------------------------
# Root access key alarm — #165
# ---------------------------------------------------------------------------------------------------------------------
# AWS Config managed rule `iam-root-access-key-check` reports a NON_COMPLIANT
# evaluation whenever the root user has an active access key in this account.
# The rule itself does not raise a CloudWatch alarm — Config publishes findings
# to its findings stream, which is forwarded to SecurityHub (#164) and to the
# centralized findings bucket. Combined, that is the alarm pathway.
#
# Why a Config rule instead of a CloudWatch metric alarm?
#  - There is no CloudWatch metric for "root access key exists." The supported
#    AWS-native primitive is exactly this Config managed rule.
#  - Config rules are organization-aware via aggregator (#162), so a single
#    eval surfaces non-compliance across every account.
#
# The rule is gated on `enable_root_access_key_alarm = true` so accounts that
# don't yet have Config enabled don't get a dangling resource. Once Config is
# enabled per-account (see #162) the rule will automatically begin evaluating.

resource "aws_config_config_rule" "iam_root_access_key_check" {
  count = var.enable_root_access_key_alarm ? 1 : 0

  name        = "${var.name_prefix}iam-root-access-key-check"
  description = "Reports NON_COMPLIANT if the root user has an active access key. Closes #165."

  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }

  # The rule depends on Config being enabled in this account (a recorder must
  # exist). The optional explicit dependency lets callers wire that ordering;
  # if left empty, Terraform will plan/apply this rule independently and AWS
  # will return the rule once Config exists.
  depends_on = [aws_iam_account_password_policy.pci_dss]

  tags = merge(var.tags, {
    Name          = "${var.name_prefix}iam-root-access-key-check"
    Purpose       = "iam-baseline-root-key-alarm"
    pci-dss-scope = "true"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Identity Center (SSO) MFA Configuration
# ---------------------------------------------------------------------------------------------------------------------
# SSO MFA enforcement MUST be configured via the AWS IAM Identity Center console.
# Terraform/provider support for SSO MFA settings is limited.
#
# Manual steps required (PCI-DSS Req 8.3):
#   1. Go to AWS IAM Identity Center in the management account
#   2. Settings > Authentication > Multi-factor authentication
#   3. Configure MFA:
#      - Prompt users for MFA: "Every time they sign in"
#      - Users can authenticate with these MFA types: "Security key" and "Authenticator app"
#      - If a user does not yet have a registered MFA device:
#        "Require them to register an MFA device at sign in"
#   4. Save changes
#
# These settings ensure all SSO users must enroll and use MFA on every login,
# satisfying PCI-DSS Requirement 8.3.1 (MFA for all non-console access to the CDE)
# and Requirement 8.3.2 (MFA for all remote network access).
# ---------------------------------------------------------------------------------------------------------------------
