# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-abac-iam — least-privilege + ABAC IAM role for ML workloads (EKS Pod Identity)
# ---------------------------------------------------------------------------------------------------------------------
# ADR-0018 (EKS Pod Identity as the default workload identity) + ADR-0028 (the ABAC
# condition: aws:PrincipalTag/platform:system == aws:ResourceTag/platform:system) +
# ADR-0048 (the S3 artifact store / RDS-Secrets this role reaches). WS-E owns the
# least-privilege + ABAC delta; the broad keyless posture is ADR-0018.
#
# The permission policy is least-privilege (only the S3/KMS/Secrets actions the ML
# pipeline needs) AND every statement carries the ABAC tag-match condition, so a pod
# bound to this role may only act on resources whose `platform:system` ResourceTag
# equals the role's `platform:system` PrincipalTag — cross-system access is denied even
# if the ARN is listed.
#
# APPLY-GATED / DEFAULT-OFF: gated by `var.enabled` (default false) via `count`. With
# defaults, `terraform plan` creates ZERO IAM. IAM is identity-critical; enabling
# requires an explicit human apply.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  create              = var.enabled
  role_name           = "${var.name}-role"
  policy_name         = "${var.name}-policy"
  create_pod_identity = var.enabled && var.eks_cluster_name != ""
  has_buckets         = length(var.artifact_bucket_arns) > 0
  has_kms             = length(var.kms_key_arns) > 0
  has_secrets         = length(var.secret_arns) > 0
  bucket_object_arns  = [for arn in var.artifact_bucket_arns : "${arn}/*"]

  # ADR-0028 taxonomy: derive defaults from platform_system; allow caller override via var.tags.
  base_tags = {
    "platform:system"     = var.platform_system
    "platform:component"  = "ml-iam"
    "platform:owner"      = "team-ml-platform"
    "platform:managed-by" = "terragrunt"
  }
  effective_tags = merge(local.base_tags, var.tags)
}

# ---------------------------------------------------------------------------------------------------------------------
# Trust policy — EKS Pod Identity (pods.eks.amazonaws.com) assumes the role and is
# stamped with the platform:system session tag used by the ABAC condition (ADR-0018).
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "EksPodIdentityAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # Pod Identity injects the principal tag platform:system from the role's own tag;
    # this condition asserts the session is tagged with the expected system.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/platform:system"
      values   = [var.platform_system]
    }
  }
}

resource "aws_iam_role" "this" {
  count = local.create ? 1 : 0

  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = local.effective_tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Least-privilege permission policy — only the actions the ML pipeline needs, each
# statement carrying the ADR-0028 ABAC tag-match condition so access is scoped to the
# role's own platform:system. Statements are emitted only when their resource list is
# non-empty (no wildcard, no empty-resource statements).
# ---------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "permissions" {
  # S3 object read/write on the artifact store, ABAC-scoped.
  dynamic "statement" {
    for_each = local.has_buckets ? [1] : []
    content {
      sid    = "ArtifactStoreObjectsAbac"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = local.bucket_object_arns

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/platform:system"
        values   = ["$${aws:PrincipalTag/platform:system}"]
      }
    }
  }

  # S3 bucket-level list on the artifact store, ABAC-scoped.
  dynamic "statement" {
    for_each = local.has_buckets ? [1] : []
    content {
      sid    = "ArtifactStoreListAbac"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      resources = var.artifact_bucket_arns

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/platform:system"
        values   = ["$${aws:PrincipalTag/platform:system}"]
      }
    }
  }

  # KMS decrypt/data-key for SSE-KMS, ABAC-scoped.
  dynamic "statement" {
    for_each = local.has_kms ? [1] : []
    content {
      sid    = "ArtifactStoreKmsAbac"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
      ]
      resources = var.kms_key_arns

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/platform:system"
        values   = ["$${aws:PrincipalTag/platform:system}"]
      }
    }
  }

  # Secrets Manager read (MLflow RDS creds via ESO), ABAC-scoped.
  dynamic "statement" {
    for_each = local.has_secrets ? [1] : []
    content {
      sid    = "MlSecretsReadAbac"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = var.secret_arns

      condition {
        test     = "StringEquals"
        variable = "aws:ResourceTag/platform:system"
        values   = ["$${aws:PrincipalTag/platform:system}"]
      }
    }
  }
}

resource "aws_iam_policy" "this" {
  count = local.create ? 1 : 0

  name        = local.policy_name
  description = "Least-privilege + ABAC (platform:system tag-match) permissions for ${var.platform_system} ML workloads (ADR-0018/0028/0048)"
  policy      = data.aws_iam_policy_document.permissions.json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this[0].arn
}

# ---------------------------------------------------------------------------------------------------------------------
# EKS Pod Identity association — binds the workload ServiceAccount to the role (ADR-0018).
# Only created when an EKS cluster name is supplied; the role tag platform:system is
# what Pod Identity surfaces as the ABAC principal tag.
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_eks_pod_identity_association" "this" {
  count = local.create_pod_identity ? 1 : 0

  cluster_name    = var.eks_cluster_name
  namespace       = var.service_account_namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.this[0].arn

  tags = local.effective_tags
}
