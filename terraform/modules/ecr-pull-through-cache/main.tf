# -----------------------------------------------------------------------------
# ECR Pull-Through Cache (ADR-0029)
# -----------------------------------------------------------------------------
# Mirrors public upstream registries (Docker Hub, Quay, GHCR, registry.k8s.io,
# public.ecr.aws, GitLab) into this account's private ECR registry to defeat
# Docker Hub rate-limits and external-registry outages. Cached repositories are
# auto-created on first pull by the repository creation template with KMS
# encryption, immutable tags, a lifecycle policy, and scan-on-push.
#
# Callers pull as:
#   <acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<upstream-image>
# e.g.  <acct>.dkr.ecr.eu-west-1.amazonaws.com/docker-hub/library/nginx:1.27
# -----------------------------------------------------------------------------

locals {
  # Upstreams that need an upstream credential (e.g. Docker Hub).
  credentialed_upstreams = {
    for k, v in var.upstreams : k => v if try(v.requires_credential, false)
  }

  # The custom IAM role is mandatory for the repository creation template when
  # it uses KMS encryption and/or resource tags (AWS requirement).
  create_template_role = var.create_repository_creation_template

  # ecr_repository_prefix values managed by the creation template + scanning.
  cache_prefixes = [for k, v in var.upstreams : "${k}/*"]
}

# -----------------------------------------------------------------------------
# Upstream credentials (Docker Hub) — Secrets Manager, ecr-pullthroughcache/ prefix
# -----------------------------------------------------------------------------
# AWS requires the secret name to start with `ecr-pullthroughcache/`. The value
# is a placeholder here; the real Docker Hub username + access token are injected
# out-of-band (ESO / secure pipeline) and ignored on subsequent applies.
resource "aws_secretsmanager_secret" "dockerhub" {
  for_each = local.credentialed_upstreams

  name        = "ecr-pullthroughcache/${each.key}"
  description = "Upstream credential for ECR Pull-Through Cache rule '${each.key}' (${each.value.upstream_registry_url})"
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  for_each = local.credentialed_upstreams

  secret_id     = aws_secretsmanager_secret.dockerhub[each.key].id
  secret_string = var.dockerhub_secret_placeholder

  lifecycle {
    # Real credentials are rotated out-of-band; do not clobber them.
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Pull-through cache rules — one per upstream
# -----------------------------------------------------------------------------
resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = var.upstreams

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url

  credential_arn = try(each.value.requires_credential, false) ? aws_secretsmanager_secret.dockerhub[each.key].arn : null
}

# -----------------------------------------------------------------------------
# IAM role used by the repository creation template
# -----------------------------------------------------------------------------
# Required whenever the creation template applies KMS encryption or resource
# tags. ECR assumes this role to create the cached repository on first pull.
locals {
  template_assume_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EcrPtcAssume"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "pullthroughcache.ecr.amazonaws.com" }
      },
    ]
  })

  template_permissions_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "CreateCachedRepositories"
          Effect = "Allow"
          Action = [
            "ecr:CreateRepository",
            "ecr:ReplicateImage",
            "ecr:BatchImportUpstreamImage",
            "ecr:TagResource",
            "ecr:PutLifecyclePolicy",
            "ecr:SetRepositoryPolicy",
          ]
          Resource = "*"
        },
      ],
      var.kms_key_arn != null ? [
        {
          Sid    = "KmsForCachedRepositories"
          Effect = "Allow"
          Action = [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:GenerateDataKey",
            "kms:CreateGrant",
            "kms:DescribeKey",
          ]
          Resource = var.kms_key_arn
        },
      ] : []
    )
  })
}

resource "aws_iam_role" "template" {
  count = local.create_template_role ? 1 : 0

  name               = "ecr-ptc-repo-creation"
  assume_role_policy = local.template_assume_policy
  description        = "Role assumed by ECR Pull-Through Cache to create cached repositories (ADR-0029)."

  tags = var.tags
}

resource "aws_iam_role_policy" "template" {
  count = local.create_template_role ? 1 : 0

  name   = "ecr-ptc-repo-creation"
  role   = aws_iam_role.template[0].id
  policy = local.template_permissions_policy
}

# -----------------------------------------------------------------------------
# Repository creation template — auto-configures cached repos on first pull
# -----------------------------------------------------------------------------
# `prefix = "ROOT"` applies to every cached repository created by PTC across all
# the rules above. KMS encryption + resource tags drive the custom_role_arn.
resource "aws_ecr_repository_creation_template" "this" {
  count = var.create_repository_creation_template ? 1 : 0

  prefix      = "ROOT"
  description = "Auto-config for ECR Pull-Through Cache repositories (ADR-0029)"
  applied_for = ["PULL_THROUGH_CACHE"]

  image_tag_mutability = var.image_tag_mutability
  custom_role_arn      = aws_iam_role.template[0].arn

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_image_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
    ]
  })

  resource_tags = var.tags
}

# -----------------------------------------------------------------------------
# Registry scanning configuration — scan cached repos on push
# -----------------------------------------------------------------------------
# The registry scanning configuration is a singleton per registry. We scan the
# cache prefixes on push (BASIC) or continuously (ENHANCED/Inspector).
resource "aws_ecr_registry_scanning_configuration" "this" {
  count = var.create_registry_scanning_configuration ? 1 : 0

  scan_type = var.scan_type

  dynamic "rule" {
    for_each = toset(local.cache_prefixes)

    content {
      scan_frequency = var.scan_type == "ENHANCED" ? "CONTINUOUS_SCAN" : "SCAN_ON_PUSH"

      repository_filter {
        filter      = rule.value
        filter_type = "WILDCARD"
      }
    }
  }
}
