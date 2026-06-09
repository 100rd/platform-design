# ---------------------------------------------------------------------------------------------------------------------
# GitHub Actions OIDC Provider and IAM Roles
# ---------------------------------------------------------------------------------------------------------------------
# Enables keyless authentication from GitHub Actions to AWS — no long-lived keys.
# Uses terraform-aws-modules/iam v6.x for the OIDC provider and roles.
#
# v6.0 removed the GitHub-specific submodules (iam-github-oidc-provider /
# iam-github-oidc-role). This module now uses the generic v6.x submodules:
#   - iam-oidc-provider  : generic OIDC provider (we pass the GitHub URL + audience)
#   - iam-role           : generic IAM role with built-in GitHub OIDC trust
#                          (enable_github_oidc = true)
#
# Three role types (mirroring infra):
#   terraform   — plan + apply workflows (scoped per-account-type policy from policies.tf,
#                 NOT AdministratorAccess; see docs/iam-ci-role.md and issue #173)
#   readonly    — PR plan-only workflows (ReadOnlyAccess, scoped to pull_request)
#   ecr-push    — container build workflows (ECR push policy, scoped to main + tags)
#
# Deploy in every account that CI workflows need to access.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# Resolve the single scoped Terraform policy for this account.
# ---------------------------------------------------------------------------------------------------------------------
# policies.tf defines four count-gated aws_iam_policy resources; exactly one is
# created per account (account-type routing via local.dedicated_scoped_accounts).
# one(...) returns that single ARN (or null when the count is 0), and coalesce
# picks whichever dedicated policy matched, falling back to the catch-all
# workload policy. The workload policy is created for every non-dedicated
# account, so terraform_scoped_policy_arn is ALWAYS a concrete ARN — never null,
# never AdministratorAccess.
locals {
  terraform_scoped_policy_arn = coalesce(
    one(aws_iam_policy.log_archive[*].arn),
    one(aws_iam_policy.network[*].arn),
    one(aws_iam_policy.shared[*].arn),
    one(aws_iam_policy.workload[*].arn),
  )

  # GitHub Actions OIDC identity provider endpoint + audience. The v6.x
  # iam-oidc-provider submodule is generic, so the GitHub URL/audience that the
  # old iam-github-oidc-provider hard-coded must now be passed explicitly.
  github_oidc_url      = "https://token.actions.githubusercontent.com"
  github_oidc_audience = "sts.amazonaws.com"
}

# OIDC Provider (one per AWS account — idempotent creation)
module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.6.1"

  url            = local.github_oidc_url
  client_id_list = [local.github_oidc_audience]

  tags = var.tags
}

# Terraform CI/CD role — used by plan/apply workflows
module "terraform_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.6.1"

  name            = "${var.project}-${var.account_name}-terraform"
  use_name_prefix = false

  enable_github_oidc = true

  oidc_subjects = concat(
    ["repo:${var.repository}:ref:refs/heads/${var.branch}"],
    ["repo:${var.repository}:environment:${var.account_name}"],
    var.extra_subjects,
  )

  # Scoped, per-account-type policy from policies.tf — replaces AdministratorAccess (issue #173).
  policies = {
    TerraformScoped = local.terraform_scoped_policy_arn
  }

  tags = var.tags

  depends_on = [module.github_oidc_provider]
}

# Read-only role — used by PR plan workflows (safe, no write access)
module "readonly_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.6.1"

  name            = "${var.project}-${var.account_name}-terraform-plan"
  use_name_prefix = false

  enable_github_oidc = true

  oidc_subjects = [
    "repo:${var.repository}:pull_request",
  ]

  policies = {
    ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  tags = var.tags

  depends_on = [module.github_oidc_provider]
}

# ECR push role — used by application CI workflows to build and push images
module "ecr_push_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.6.1"

  name            = "${var.project}-${var.account_name}-ecr-push"
  use_name_prefix = false

  enable_github_oidc = true

  # Exact (StringEquals) subject: pushes to the default branch.
  oidc_subjects = [
    "repo:${var.repository}:ref:refs/heads/${var.branch}",
  ]

  # Wildcard (StringLike) subject: any tag. v6.x routes wildcard subjects to a
  # separate input so the trust policy uses StringLike instead of StringEquals.
  oidc_wildcard_subjects = [
    "repo:${var.repository}:ref:refs/tags/*",
  ]

  policies = {
    ECRPush = aws_iam_policy.ecr_push.arn
  }

  tags = var.tags

  depends_on = [module.github_oidc_provider]
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
