# ---------------------------------------------------------------------------------------------------------------------
# Break-glass User — Emergency IAM Access (ADR-0011)
# ---------------------------------------------------------------------------------------------------------------------
# Single emergency-access IAM user per account. Used ONLY when SSO / Identity
# Center is unavailable (control-plane outage, mis-configured permission set,
# accidental SSO org detachment).
#
# Guarantees mandated by ADR-0011:
#   - lifecycle { prevent_destroy = true }  — plan-time protection: the user can
#     never appear in any destroy plan (targeted destroy, full destroy, stray
#     `moved` block) until the lifecycle block is deliberately removed via PR.
#   - force_destroy = false                 — apply-time backstop: Terraform fails
#     if it tries to delete the user while attached policies exist.
#
# MFA is enforced via an inline deny-without-MFA policy. The initial access key
# (and optional console password) are created once and stored in the team
# password manager; rotation is manual by design.
#
# Companion: docs/break-glass-procedure.md
# Source-of-truth: infra ADR-010 / modules/break-glass-user
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  user_name = "break-glass-${var.account_name}"
  default_tags = {
    Purpose        = "BreakGlass"
    ManagedBy      = "Terraform"
    Module         = "break-glass-user"
    UseRequirement = "MFA"
    ADR            = "ADR-0011"
  }
  effective_tags = merge(local.default_tags, var.tags)
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM user — protected against destruction (ADR-0011)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_user" "this" {
  name = local.user_name
  path = "/break-glass/"

  # Apply-time backstop. Removing a break-glass user erases an emergency-access
  # vector — it should be a deliberate, explicit operation.
  force_destroy = false

  tags = local.effective_tags

  lifecycle {
    # Plan-time protection mandated by ADR-0011. Terraform errors at plan time if
    # any configuration produces a destroy action for this user. To intentionally
    # remove the user: PR removing this block, get it reviewed/merged, then apply.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# MFA enforcement (inline deny-without-MFA)
# ---------------------------------------------------------------------------------------------------------------------
# Allows the user to manage *only* its own MFA device when no MFA session is
# present. Every other API call is denied unless aws:MultiFactorAuthPresent is
# true.

data "aws_iam_policy_document" "mfa_enforcement" {
  statement {
    sid    = "AllowViewAccountInfo"
    effect = "Allow"
    actions = [
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:ListVirtualMFADevices",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageOwnVirtualMFADevice"
    effect = "Allow"
    actions = [
      "iam:CreateVirtualMFADevice",
      "iam:DeleteVirtualMFADevice",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:mfa/$${aws:username}",
    ]
  }

  statement {
    sid    = "AllowManageOwnUserMFA"
    effect = "Allow"
    actions = [
      "iam:DeactivateMFADevice",
      "iam:EnableMFADevice",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}",
    ]
  }

  statement {
    sid    = "DenyAllExceptListedIfNoMFA"
    effect = "Deny"
    not_actions = [
      "iam:CreateVirtualMFADevice",
      "iam:EnableMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ListVirtualMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken",
    ]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_user_policy" "mfa_enforcement" {
  name   = "${var.name_prefix}${local.user_name}-mfa-enforcement"
  user   = aws_iam_user.this.name
  policy = data.aws_iam_policy_document.mfa_enforcement.json
}

# ---------------------------------------------------------------------------------------------------------------------
# Administrator policy (effective only with an MFA-present session)
# ---------------------------------------------------------------------------------------------------------------------
# Combined with the inline deny above, this grants full admin ONLY AFTER the user
# enrolls an MFA device and calls sts:GetSessionToken with --serial-number.

resource "aws_iam_user_policy_attachment" "administrator_access" {
  user       = aws_iam_user.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------------------------------------------------------------
# Console login profile (optional — for emergency console access when SSO is down)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_user_login_profile" "this" {
  count                   = var.create_console_login ? 1 : 0
  user                    = aws_iam_user.this.name
  password_reset_required = true

  lifecycle {
    # The generated password is only meaningful at creation time. Ignore later
    # drift so the password isn't reset on every apply.
    ignore_changes = [password_reset_required]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Initial access key (stored once in the team password manager, rotated manually)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_access_key" "this" {
  count = var.create_access_key ? 1 : 0
  user  = aws_iam_user.this.name
}

# ---------------------------------------------------------------------------------------------------------------------
# CloudWatch alarm on break-glass usage
# ---------------------------------------------------------------------------------------------------------------------
# Only creates the alarm chain if both the CloudTrail log group AND an SNS topic
# ARN are supplied. The org-wide CloudTrail trail must already deliver to
# var.cloudtrail_log_group_name.

resource "aws_cloudwatch_log_metric_filter" "usage" {
  count          = var.cloudtrail_log_group_name != "" && var.alarm_sns_topic_arn != "" ? 1 : 0
  name           = "${var.name_prefix}${local.user_name}-usage"
  log_group_name = var.cloudtrail_log_group_name

  # Triggers on any CloudTrail event where userIdentity.userName matches the
  # break-glass user, regardless of action.
  pattern = "{ $.userIdentity.userName = \"${local.user_name}\" }"

  metric_transformation {
    name      = "${local.user_name}-event-count"
    namespace = "BreakGlass"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "usage" {
  count               = var.cloudtrail_log_group_name != "" && var.alarm_sns_topic_arn != "" ? 1 : 0
  alarm_name          = "${var.name_prefix}${local.user_name}-used"
  alarm_description   = "Break-glass user ${local.user_name} authenticated against account ${data.aws_caller_identity.current.account_id}. Investigate within 1 business hour."
  namespace           = "BreakGlass"
  metric_name         = "${local.user_name}-event-count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_sns_topic_arn]
  ok_actions          = []
  tags                = local.effective_tags
}
