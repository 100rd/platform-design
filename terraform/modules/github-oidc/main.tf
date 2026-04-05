# ---------------------------------------------------------------------------------------------------------------------
# GitHub Actions OIDC Provider and IAM Roles
# ---------------------------------------------------------------------------------------------------------------------
# Enables keyless authentication from GitHub Actions to AWS — no long-lived keys.
# Uses terraform-aws-modules/iam v6.x for the OIDC provider and roles.
#
# Three role types (mirroring infra):
#   terraform   — plan + apply workflows (AdministratorAccess, scoped to main + PR + environment)
#   readonly    — PR plan-only workflows (ReadOnlyAccess, scoped to pull_request)
#   ecr-push    — container build workflows (ECR push policy, scoped to main + tags)
#
# Deploy in every account that CI workflows need to access.
# ---------------------------------------------------------------------------------------------------------------------

# OIDC Provider (one per AWS account — idempotent creation)
module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "6.4.0"

  tags = var.tags
}

# Terraform CI/CD role — used by plan/apply workflows
module "terraform_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "6.4.0"

  name = "${var.project}-${var.account_name}-terraform"

  subjects = concat(
    ["repo:${var.repository}:ref:refs/heads/${var.branch}"],
    ["repo:${var.repository}:pull_request"],
    ["repo:${var.repository}:environment:${var.account_name}"],
    var.extra_subjects,
  )

  policies = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  tags = var.tags
}

# Read-only role — used by PR plan workflows (safe, no write access)
module "readonly_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "6.4.0"

  name = "${var.project}-${var.account_name}-terraform-plan"

  subjects = [
    "repo:${var.repository}:pull_request",
  ]

  policies = {
    ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  tags = var.tags
}

# ECR push role — used by application CI workflows to build and push images
module "ecr_push_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "6.4.0"

  name = "${var.project}-${var.account_name}-ecr-push"

  subjects = [
    "repo:${var.repository}:ref:refs/heads/${var.branch}",
    "repo:${var.repository}:ref:refs/tags/*",
  ]

  policies = {
    ECRPush = aws_iam_policy.ecr_push.arn
  }

  tags = var.tags
}

# ECR push IAM policy — least-privilege for image publishing
resource "aws_iam_policy" "ecr_push" {
  name        = "${var.project}-${var.account_name}-ecr-push"
  description = "Allow GitHub Actions to push container images to ECR repositories"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project}/*"
      },
    ]
  })

  tags = var.tags
}
