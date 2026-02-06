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
