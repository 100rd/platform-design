# ---------------------------------------------------------------------------------------------------------------------
# Service Control Policies
# ---------------------------------------------------------------------------------------------------------------------
# EXEMPTION PHILOSOPHY (mirroring infra issue #67):
# - OrganizationAccountAccessRole: exempt ONLY from region restriction
#   (needs to call global services like IAM, STS during account vending)
# - platform-design-terraform-*: exempt ONLY where Terraform legitimately operates
#   outside allowed regions (global services: IAM, ACM, Route53, CloudFront)
# - Security SCPs (CloudTrail, GuardDuty): NO exemptions — these protect
#   the audit trail. Terraform must not touch these outside the dedicated org-trail
#   module which runs under the management account.
# - S3 public access: terraform roles exempt (they manage public access blocks)
# - EBS encryption: no exemptions (Terraform must create encrypted volumes)
#
# OU LIMIT NOTE:
# AWS limits 5 SCPs per target (including inherited FullAWSAccess from root).
# We attach <=5 SCPs to target_ou_ids (per-OU level):
#   deny_leave_org, deny_root_account (workloads), restrict_regions,
#   deny_cloudtrail_changes, deny_guardduty_changes
# We attach 2 SCPs to root_ids (root level — applies to all accounts):
#   deny_s3_public, require_ebs_encryption
# We attach 1 SCP to suspended OU:
#   deny_all_suspended
# ---------------------------------------------------------------------------------------------------------------------

# Deny leaving the organization
resource "aws_organizations_policy" "deny_leave_org" {
  name        = "DenyLeaveOrganization"
  description = "Prevents member accounts from leaving the organization"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyLeaveOrg"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Deny disabling CloudTrail
# NO exemptions — Terraform must not modify CloudTrail outside the dedicated org-trail module.
resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  name        = "DenyDisableCloudTrail"
  description = "Prevents disabling or deleting CloudTrail logs — no exemptions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailModification"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Deny root account usage
resource "aws_organizations_policy" "deny_root_account" {
  name        = "DenyRootAccountUsage"
  description = "Denies all actions by root user in member accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyRootUser"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Region restriction — allow only EU regions + us-east-1 for global services
# Exemptions (mirroring infra issue #67):
# - OrganizationAccountAccessRole: needs to call global services (IAM, STS, ACM,
#   CloudFront, Route53) during account vending operations
# - platform-design-terraform-*: Terraform manages global resources (IAM roles, ACM certs,
#   CloudFront distributions) that require us-east-1 API calls
resource "aws_organizations_policy" "restrict_regions" {
  name        = "RestrictToEURegions"
  description = "Restricts resource creation to EU regions — exempt global-service callers"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyNonEURegions"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
          ArnNotLike = {
            "aws:PrincipalArn" = [
              # Account vending / Control Tower requires global service access
              "arn:aws:iam::*:role/OrganizationAccountAccessRole",
              # Terraform manages IAM, ACM (us-east-1), CloudFront, Route53
              "arn:aws:iam::*:role/${var.project}-terraform-*",
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Deny disabling GuardDuty
# NO exemptions — GuardDuty is managed via delegated admin in the security account only.
resource "aws_organizations_policy" "deny_guardduty_changes" {
  name        = "DenyGuardDutyChanges"
  description = "Prevent disabling GuardDuty — managed via delegated admin only, no exemptions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyGuardDutyChanges"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:UpdateDetector",
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Deny S3 public access — attached at ROOT level to avoid per-OU SCP limit.
# Exemption: platform-design-terraform-* roles only (they set PublicAccessBlock on buckets).
# OrganizationAccountAccessRole has no legitimate need to change public access settings.
resource "aws_organizations_policy" "deny_s3_public" {
  name        = "DenyS3PublicAccess"
  description = "Prevent S3 buckets from being made public — terraform roles exempt"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyS3PublicAccess"
        Effect = "Deny"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutAccountPublicAccessBlock",
        ]
        Resource = "*"
        Condition = {
          ArnNotLike = {
            # Terraform manages public access blocks (always setting them to block)
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:role/${var.project}-terraform-*",
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Require EBS encryption — attached at ROOT level to avoid per-OU SCP limit.
# NO exemptions — Terraform must always create encrypted EBS volumes.
resource "aws_organizations_policy" "require_ebs_encryption" {
  name        = "RequireEBSEncryption"
  description = "Deny creation of unencrypted EBS volumes — no exemptions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyUnencryptedEBS"
        Effect   = "Deny"
        Action   = "ec2:CreateVolume"
        Resource = "*"
        Condition = {
          Bool = {
            "ec2:Encrypted" = "false"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Deny all actions in Suspended OU — accounts moved here are quarantined.
# OrganizationAccountAccessRole retains access for:
# - Break-glass emergency operations
# - CloudTrail/Config log retrieval (service principals, not affected by ArnNotLike)
# - Executing the offboarding runbook
resource "aws_organizations_policy" "deny_all_suspended" {
  name        = "DenyAllSuspended"
  description = "Deny all actions in Suspended OU — only OAAR retains access for audit/closure"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyAllSuspended"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          ArnNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:role/OrganizationAccountAccessRole",
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachments — per OU
# ---------------------------------------------------------------------------------------------------------------------

# Attach deny-leave-org to all OUs
resource "aws_organizations_policy_attachment" "deny_leave_org" {
  for_each = { for k, v in var.ou_ids : k => v if k != "Root" }

  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = each.value
}

# Attach deny-disable-cloudtrail to all OUs
resource "aws_organizations_policy_attachment" "deny_disable_cloudtrail" {
  for_each = { for k, v in var.ou_ids : k => v if k != "Root" }

  policy_id = aws_organizations_policy.deny_disable_cloudtrail.id
  target_id = each.value
}

# Attach deny-root to workload OUs only
resource "aws_organizations_policy_attachment" "deny_root_account" {
  for_each = { for k, v in var.ou_ids : k => v if contains(var.workload_ou_names, k) }

  policy_id = aws_organizations_policy.deny_root_account.id
  target_id = each.value
}

# Attach region restriction to all non-root OUs
resource "aws_organizations_policy_attachment" "restrict_regions" {
  for_each = { for k, v in var.ou_ids : k => v if k != "Root" }

  policy_id = aws_organizations_policy.restrict_regions.id
  target_id = each.value
}

# Attach deny-guardduty-changes to all non-root OUs (workloads OU level)
resource "aws_organizations_policy_attachment" "deny_guardduty_changes" {
  for_each = { for k, v in var.ou_ids : k => v if k != "Root" }

  policy_id = aws_organizations_policy.deny_guardduty_changes.id
  target_id = each.value
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachments — ROOT level
# Broad security SCPs avoid the 5-SCP-per-OU limit. Apply to all accounts in the org.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "deny_s3_public" {
  for_each = toset(var.root_ids)

  policy_id = aws_organizations_policy.deny_s3_public.id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "require_ebs_encryption" {
  for_each = toset(var.root_ids)

  policy_id = aws_organizations_policy.require_ebs_encryption.id
  target_id = each.value
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachments — Suspended OU
# Only created when suspended_ou_id is provided (non-empty).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "deny_all_suspended" {
  count = var.suspended_ou_id != "" ? 1 : 0

  policy_id = aws_organizations_policy.deny_all_suspended.id
  target_id = var.suspended_ou_id
}
