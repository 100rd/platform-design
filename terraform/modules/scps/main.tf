# ---------------------------------------------------------------------------------------------------------------------
# Service Control Policies
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
resource "aws_organizations_policy" "deny_disable_cloudtrail" {
  name        = "DenyDisableCloudTrail"
  description = "Prevents disabling or deleting CloudTrail logs"
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

# Region restriction — allow only EU regions
resource "aws_organizations_policy" "restrict_regions" {
  name        = "RestrictToEURegions"
  description = "Restricts resource creation to EU regions plus us-east-1 (for global services)"
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
            "aws:RequestedRegion" = [
              "eu-west-1",
              "eu-west-2",
              "eu-west-3",
              "eu-central-1",
              "us-east-1",
            ]
          }
          # Exclude global services that only work in us-east-1
          "ForAnyValue:StringNotLike" = {
            "aws:PrincipalServiceName" = [
              "organizations.amazonaws.com",
              "iam.amazonaws.com",
              "sts.amazonaws.com",
              "support.amazonaws.com",
              "health.amazonaws.com",
            ]
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Deny public S3 buckets in prod
resource "aws_organizations_policy" "deny_public_s3_prod" {
  name        = "DenyPublicS3InProd"
  description = "Prevents creating publicly accessible S3 buckets in Prod OU"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicS3"
        Effect = "Deny"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutAccountPublicAccessBlock",
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "s3:PublicAccessBlockConfiguration/BlockPublicAcls"   = "true"
            "s3:PublicAccessBlockConfiguration/BlockPublicPolicy" = "true"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Policy Attachments
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
  for_each = { for k, v in var.ou_ids : k => v if contains(["NonProd", "Prod"], k) }

  policy_id = aws_organizations_policy.deny_root_account.id
  target_id = each.value
}

# Attach region restriction to all non-root OUs
resource "aws_organizations_policy_attachment" "restrict_regions" {
  for_each = { for k, v in var.ou_ids : k => v if k != "Root" }

  policy_id = aws_organizations_policy.restrict_regions.id
  target_id = each.value
}

# Attach deny-public-S3 to Prod OU only
resource "aws_organizations_policy_attachment" "deny_public_s3_prod" {
  for_each = { for k, v in var.ou_ids : k => v if k == "Prod" }

  policy_id = aws_organizations_policy.deny_public_s3_prod.id
  target_id = each.value
}
