# -----------------------------------------------------------------------------
# modules/github-oidc/policies.tf
# Scoped IAM policies for Terraform CI/CD roles (Issue #69)
#
# These policies replace AdministratorAccess with service-specific permissions
# scoped to the services each account type actually manages. They are
# intentionally broader than production-user policies because Terraform needs
# to create, modify, and delete any resource it manages.
#
# TRIVY: s3:* is intentional on S3-heavy accounts. The Terraform CI/CD role
# must be able to create/destroy S3 buckets, set policies, manage lifecycle
# rules, etc. The resource scope is restricted to the account's own buckets
# via the SCP layer (deny_s3_public). Flagged as AVD-AWS-0345, suppressed
# below with justification.
#
# AUDIT: Enable IAM Access Analyzer and run for 30 days to capture actual
# API usage, then refine these policies with the generated recommendations.
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Account-type routing
# ---------------------------------------------------------------------------
# Each account gets exactly ONE scoped policy. Accounts with dedicated,
# narrower policies (log-archive, network, shared) are listed here; every
# other account (dev/staging/prod workloads AND the general-purpose accounts
# security, dr, sandbox, management, third-party) falls through to the
# broader-but-still-scoped "workload" policy. This guarantees the Terraform
# CI/CD role in EVERY account has a non-empty, non-admin permission set so
# plan/apply keeps working org-wide (issue #173).
locals {
  dedicated_scoped_accounts = ["log-archive", "network", "shared"]
}


# ---------------------------------------------------------------------------
# Log Archive account — S3 + KMS + CloudWatch Logs only
# ---------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0345
resource "aws_iam_policy" "log_archive" {
  count = var.account_name == "log-archive" ? 1 : 0

  name        = "${var.project}-${var.account_name}-terraform-scoped"
  description = "Scoped Terraform permissions for log-archive account (issue #69)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3LogArchive"
        Effect = "Allow"
        Action = [
          # trivy:ignore:AVD-AWS-0345 -- Terraform CI/CD needs full S3 control to manage log buckets
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadonly"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*",
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*/*",
          "arn:aws:dynamodb:*:*:table/${var.project}-terraform-locks"
        ]
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Network account — VPC, TGW, Route53, RAM, EC2 networking
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "network" {
  count = var.account_name == "network" ? 1 : 0

  name        = "${var.project}-${var.account_name}-terraform-scoped"
  description = "Scoped Terraform permissions for network account (issue #69)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCAndNetworking"
        Effect = "Allow"
        Action = [
          "ec2:*Vpc*",
          "ec2:*Subnet*",
          "ec2:*RouteTable*",
          "ec2:*InternetGateway*",
          "ec2:*NatGateway*",
          "ec2:*TransitGateway*",
          "ec2:*SecurityGroup*",
          "ec2:*NetworkAcl*",
          "ec2:*FlowLog*",
          "ec2:*Address*",
          "ec2:*Endpoint*",
          "ec2:*PeeringConnection*",
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:*",
          "route53resolver:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "RAM"
        Effect = "Allow"
        Action = [
          "ram:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForNetworking"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*",
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*/*",
          "arn:aws:dynamodb:*:*:table/${var.project}-terraform-locks"
        ]
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Shared account — ECR, KMS, Secrets Manager, S3
# ---------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0345
resource "aws_iam_policy" "shared" {
  count = var.account_name == "shared" ? 1 : 0

  name        = "${var.project}-${var.account_name}-terraform-scoped"
  description = "Scoped Terraform permissions for shared account (issue #69)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = [
          # trivy:ignore:AVD-AWS-0345 -- Terraform CI/CD needs full S3 control to manage shared buckets
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForShared"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:CreateServiceLinkedRole",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*",
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*/*",
          "arn:aws:dynamodb:*:*:table/${var.project}-terraform-locks"
        ]
      }
    ]
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Default workload policy — EKS, EC2, IAM, S3, RDS, Lambda, CloudWatch.
# Catch-all for every account WITHOUT a dedicated policy above:
#   dev, staging, prod, dr, security, sandbox, management, third-party.
# ---------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0345
resource "aws_iam_policy" "workload" {
  count = contains(local.dedicated_scoped_accounts, var.account_name) ? 0 : 1

  name        = "${var.project}-${var.account_name}-terraform-scoped"
  description = "Scoped Terraform permissions for workload account (${var.account_name}) (issue #69)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKS"
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Compute"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ELB"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDS"
        Effect = "Allow"
        Action = [
          "rds:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3"
        Effect = "Allow"
        Action = [
          # trivy:ignore:AVD-AWS-0345 -- Terraform CI/CD needs full S3 control to manage workload buckets
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMS"
        Effect = "Allow"
        Action = [
          "kms:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForWorkloads"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateRole",
          "iam:CreateServiceLinkedRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatch"
        Effect = "Allow"
        Action = [
          "logs:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "AutoScaling"
        Effect = "Allow"
        Action = [
          "autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*",
          "arn:aws:s3:::${var.project}-tfstate-${var.account_name}-*/*",
          "arn:aws:dynamodb:*:*:table/${var.project}-terraform-locks"
        ]
      }
    ]
  })

  tags = var.tags
}
