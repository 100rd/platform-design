# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-artifact-store (ADR-0048 D2 / WS-B)
# ---------------------------------------------------------------------------------------------------------------------
# S3 bucket for MLflow artifact storage + IAM role with EKS Pod Identity trust
# and ABAC condition so MLflow pods authenticate without static keys.
#
# Resources (all gated on var.create_resources):
#   - aws_s3_bucket                              (versioning, SSE-KMS, ADR-0028 tags)
#   - aws_s3_bucket_ownership_controls           (BucketOwnerEnforced — IAM-only, no ACLs)
#   - aws_s3_bucket_public_access_block          (all-block)
#   - aws_s3_bucket_policy                       (DenyInsecureTransport — CIS AWS 2.1.1)
#   - aws_s3_bucket_server_side_encryption_configuration (SSE-KMS or AES256)
#   - aws_s3_bucket_versioning                   (SOC2 audit chain)
#   - aws_s3_bucket_lifecycle_configuration      (STANDARD-IA -> Glacier IR -> Expire)
#   - aws_iam_role                               (Pod Identity trust + ADR-0028 tags)
#   - aws_iam_policy                             (S3 scoped to this bucket + ABAC — standalone, CIS 1.16)
#   - aws_iam_role_policy_attachment             (binds the standalone policy to the role)
#
# ADR-0028: AWS resource tags use colon separator (platform:system) — AWS allows ':'.
# ADR-0018: EKS Pod Identity; trust policy scoped per eks_cluster_name.
# ADR-0048 D2: ABAC — only a principal tagged platform:system=ml-pipeline may
#   access a resource tagged the same way. Enforced in the role policy condition.
# CIS AWS 1.16: prefer managed (standalone) policies over inline role policies so
#   permissions are discoverable/auditable and reusable.
# CIS AWS 2.1.1: deny any S3 request not using TLS (aws:SecureTransport = false).
# ---------------------------------------------------------------------------------------------------------------------

locals {
  sse_algorithm  = var.kms_key_arn != "" ? "aws:kms" : "AES256"
  kms_master_key = var.kms_key_arn != "" ? var.kms_key_arn : null

  # Canonical ADR-0028 platform:system value driving the ABAC condition.
  platform_system = lookup(var.tags, "platform:system", "ml-pipeline")

  # Merge required ADR-0028 baseline tags so callers cannot accidentally omit them.
  effective_tags = merge(
    {
      "platform:system"     = "ml-pipeline"
      "platform:component"  = "model-registry"
      "platform:managed-by" = "terragrunt"
    },
    var.tags,
  )
}

# Data source used in the trust policy condition — account-scoped trust.
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------------------------------------------------
# S3 Bucket
# BucketOwnerEnforced = IAM-only, no per-object ACLs; mirror of GCS uniform
# bucket-level access (ADR-0048 D2).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  bucket = var.bucket_name

  tags = local.effective_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------------------------------------------------
# Bucket policy — DenyInsecureTransport (CIS AWS 2.1.1)
# Deny every S3 action on the bucket and its objects when the request is not over
# TLS (aws:SecureTransport = false). Complements the public-access block above.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "mlflow_bucket_policy" {
  count = var.create_resources ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.mlflow_artifacts[0].arn,
      "${aws_s3_bucket.mlflow_artifacts[0].arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  # Ensure the public-access block is in place before the policy is attached so a
  # transient policy evaluation can never widen access.
  depends_on = [aws_s3_bucket_public_access_block.mlflow_artifacts]

  bucket = aws_s3_bucket.mlflow_artifacts[0].id
  policy = data.aws_iam_policy_document.mlflow_bucket_policy[0].json
}

# SSE-KMS at rest; falls back to AES256 when no KMS key is provided (ADR-0048 D2).
resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.kms_master_key
    }
    bucket_key_enabled = local.sse_algorithm == "aws:kms" ? true : false
  }
}

# Object versioning — SOC2 artifact audit chain (ADR-0048 D2 / ADR-0037 D2).
resource "aws_s3_bucket_versioning" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Lifecycle: STANDARD-IA -> Glacier Instant Retrieval -> Expire.
# S3 analog of GCS Nearline -> Coldline -> Delete ladder (ADR-0048 D2).
resource "aws_s3_bucket_lifecycle_configuration" "mlflow_artifacts" {
  count = var.create_resources ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.mlflow_artifacts]

  bucket = aws_s3_bucket.mlflow_artifacts[0].id

  rule {
    id     = "mlflow-artifact-lifecycle"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.standard_ia_after_days > 0 ? [1] : []
      content {
        days          = var.standard_ia_after_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "transition" {
      for_each = var.glacier_after_days > 0 ? [1] : []
      content {
        days          = var.glacier_after_days
        storage_class = "GLACIER_IR"
      }
    }

    dynamic "expiration" {
      for_each = var.expire_after_days > 0 ? [1] : []
      content {
        days = var.expire_after_days
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.versioning_enabled && var.expire_after_days > 0 ? [1] : []
      content {
        noncurrent_days = var.expire_after_days
      }
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Role — EKS Pod Identity trust + ABAC (ADR-0018 + ADR-0048 D2)
#
# Trust: pods.eks.amazonaws.com principal, scoped to source account.
# Permission: S3 object ops on THIS bucket + ABAC condition (platform:system tag
#   on principal AND resource must both equal local.platform_system).
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "mlflow_pod_identity_trust" {
  count = var.create_resources ? 1 : 0

  statement {
    sid     = "EKSPodIdentityTrust"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # Scope trust to this AWS account so cross-account Pod Identity is blocked.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "mlflow_artifact_store" {
  count = var.create_resources ? 1 : 0

  name        = var.mlflow_pod_identity_role_name
  description = "MLflow artifact-store Pod Identity role — scoped S3 access with ABAC (ADR-0048 D2 / ADR-0018)."

  assume_role_policy = data.aws_iam_policy_document.mlflow_pod_identity_trust[0].json

  tags = local.effective_tags
}

data "aws_iam_policy_document" "mlflow_s3_abac" {
  count = var.create_resources ? 1 : 0

  # S3 object operations — bucket-scoped, ABAC-gated.
  statement {
    sid    = "MLflowS3ObjectAccessABAC"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectVersion",
    ]

    # This artifact store only, not project-wide (mirrors GCS objectAdmin scope
    # on THIS bucket — ADR-0037 D2 rationale; carried forward to ADR-0048 D2).
    resources = ["${aws_s3_bucket.mlflow_artifacts[0].arn}/*"]

    # ABAC condition: the calling principal (MLflow pod) AND the resource
    # (S3 bucket) must both be tagged platform:system = ml-pipeline.
    # A mis-tagged caller or a bucket missing the tag will be denied.
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/platform:system"
      values   = [local.platform_system]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/platform:system"
      values   = [local.platform_system]
    }
  }

  statement {
    sid    = "MLflowS3BucketListABAC"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.mlflow_artifacts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/platform:system"
      values   = [local.platform_system]
    }
  }

  # KMS decrypt/generate for SSE-KMS; skipped when kms_key_arn is empty.
  dynamic "statement" {
    for_each = var.kms_key_arn != "" ? [1] : []
    content {
      sid    = "MLflowKMSAccess"
      effect = "Allow"

      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]

      resources = [var.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalTag/platform:system"
        values   = [local.platform_system]
      }
    }
  }
}

# Standalone managed policy (CIS AWS 1.16) — discoverable/auditable, reusable, and
# decoupled from the role lifecycle (vs. an inline aws_iam_role_policy).
resource "aws_iam_policy" "mlflow_s3_abac" {
  count = var.create_resources ? 1 : 0

  name        = "${var.mlflow_pod_identity_role_name}-s3-abac"
  description = "Bucket-scoped S3 (+optional KMS) access for the MLflow artifact store, ABAC-gated on platform:system (ADR-0048 D2 / CIS AWS 1.16)."
  policy      = data.aws_iam_policy_document.mlflow_s3_abac[0].json

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "mlflow_s3_abac" {
  count = var.create_resources ? 1 : 0

  role       = aws_iam_role.mlflow_artifact_store[0].name
  policy_arn = aws_iam_policy.mlflow_s3_abac[0].arn
}
