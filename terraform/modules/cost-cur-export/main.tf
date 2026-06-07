# ---------------------------------------------------------------------------------------------------------------------
# AWS Cost and Usage Report (CUR) + Athena cloud-integration for OpenCost
# ---------------------------------------------------------------------------------------------------------------------
# Implements ADR-0027: OpenCost + AWS CUR/Athena cloud-integration.
#
# Resources created:
#   1. S3 bucket           — CUR delivery destination (Parquet, hourly, versioned, encrypted)
#   2. S3 bucket policy    — allow billingreports.amazonaws.com to deliver reports
#   3. AWS CUR report      — hourly, Parquet, resource IDs, ATHENA additional artifact
#   4. Glue database       — schema-on-read over the Parquet CUR files
#   5. Athena workgroup    — isolated query workgroup with per-query size limit
#   6. IAM role + policy   — IRSA-compatible read-only access for OpenCost
#
# cloud-integration.json fields resolved from outputs:
#   bucket    = aws_s3_bucket.cur.bucket
#   region    = var.aws_region
#   database  = aws_glue_catalog_database.cur.name
#   table     = local.glue_table_name
#   workgroup = aws_athena_workgroup.opencost.name
#   account   = data.aws_caller_identity.current.account_id
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name

  # CUR delivers files under: s3://<bucket>/<report_path_prefix>/<report_name>/
  report_s3_prefix = "${var.cur_report_prefix}/${var.cur_report_name}"

  # Glue table name: CUR report name with hyphens replaced by underscores.
  glue_table_name = replace(var.cur_report_name, "-", "_")
}

# ---------------------------------------------------------------------------------------------------------------------
# 1. S3 Bucket — CUR delivery
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket" "cur" {
  bucket        = var.cur_s3_bucket_name
  force_destroy = var.force_destroy_bucket

  tags = merge(var.tags, {
    Name    = var.cur_s3_bucket_name
    Purpose = "aws-cur-opencost"
  })
}

resource "aws_s3_bucket_versioning" "cur" {
  bucket = aws_s3_bucket.cur.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    id     = "cur-lifecycle"
    status = "Enabled"

    transition {
      days          = var.lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Athena query results — kept in a separate bucket for IAM boundary clarity.
resource "aws_s3_bucket" "athena_results" {
  bucket        = var.athena_results_bucket_name
  force_destroy = var.force_destroy_bucket

  tags = merge(var.tags, {
    Name    = var.athena_results_bucket_name
    Purpose = "athena-query-results-opencost"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "athena-results-ttl"
    status = "Enabled"

    expiration {
      # 7-day TTL — results are transient; OpenCost re-queries on schedule.
      days = 7
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 2. S3 Bucket Policy — allow billingreports.amazonaws.com to deliver CUR
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_s3.json

  depends_on = [aws_s3_bucket_public_access_block.cur]
}

data "aws_iam_policy_document" "cur_s3" {
  # Billing service ACL check
  statement {
    sid    = "BillingAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Billing service write — deliver report files
  statement {
    sid    = "BillingWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur.arn}/${local.report_s3_prefix}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # Deny unencrypted (non-TLS) access
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# 3. AWS CUR Report Definition
# ---------------------------------------------------------------------------------------------------------------------
# NOTE: CUR report definitions are a global resource that must be created in
# us-east-1.  If this module is applied in a different region, pass a
# us-east-1 provider alias to the calling module.

resource "aws_cur_report_definition" "opencost" {
  report_name = var.cur_report_name

  # Hourly granularity — smallest supported; OpenCost reconciles once per 6 h
  # but finer data gives better amortization accuracy.
  time_unit   = "HOURLY"
  format      = "Parquet"
  compression = "Parquet"

  # RESOURCES: include resource IDs so allocation can be tagged/filtered.
  additional_schema_elements = ["RESOURCES"]

  # ATHENA: generates the Glue-compatible manifest that lets Athena query
  # the Parquet files directly (schema auto-updated on each delivery).
  additional_artifacts = ["ATHENA"]

  s3_bucket = aws_s3_bucket.cur.bucket
  s3_prefix = var.cur_report_prefix
  s3_region = var.aws_region

  # OVERWRITE_REPORT: replaces the current month's data each delivery.
  # This avoids accumulating duplicate files while staying accurate.
  report_versioning      = "OVERWRITE_REPORT"
  refresh_closed_reports = true

  depends_on = [aws_s3_bucket_policy.cur]
}

# ---------------------------------------------------------------------------------------------------------------------
# 4. Glue Database
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_glue_catalog_database" "cur" {
  name        = var.glue_database_name
  description = "CUR Parquet data for OpenCost cloud-integration (ADR-0027)"

  location_uri = "s3://${aws_s3_bucket.cur.bucket}/${local.report_s3_prefix}/"
}

# ---------------------------------------------------------------------------------------------------------------------
# 5. Athena Workgroup
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_athena_workgroup" "opencost" {
  name        = var.athena_workgroup_name
  description = "OpenCost CUR cloud-integration queries (ADR-0027)"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = var.enable_athena_metrics

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    # Guard against runaway queries — OpenCost billing-period queries
    # are bounded by design, but set a hard cap for safety.
    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_cutoff
  }

  tags = merge(var.tags, {
    Name    = var.athena_workgroup_name
    Purpose = "opencost-cloud-integration"
  })
}

# ---------------------------------------------------------------------------------------------------------------------
# 6. IAM Role — IRSA for OpenCost (least-privilege: read Athena/Glue/S3)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "opencost" {
  name        = var.iam_role_name
  description = "IRSA: OpenCost reads CUR data via Athena/Glue/S3 (ADR-0027)"

  assume_role_policy = data.aws_iam_policy_document.opencost_trust.json

  tags = merge(var.tags, {
    Name    = var.iam_role_name
    Purpose = "opencost-irsa"
  })
}

data "aws_iam_policy_document" "opencost_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:oidc-provider/${var.eks_oidc_provider}"]
    }

    # Scope to the opencost ServiceAccount only — principle of least privilege.
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.opencost_namespace}:${var.opencost_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "opencost" {
  name   = "${var.iam_role_name}-policy"
  role   = aws_iam_role.opencost.id
  policy = data.aws_iam_policy_document.opencost_permissions.json
}

data "aws_iam_policy_document" "opencost_permissions" {
  # Athena — start/stop/read queries in the dedicated workgroup only.
  statement {
    sid    = "AthenaQueryAccess"
    effect = "Allow"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
      "athena:ListQueryExecutions",
      "athena:GetWorkGroup",
    ]

    resources = [aws_athena_workgroup.opencost.arn]
  }

  # Glue — read the CUR catalog only (no write, no create, no delete).
  statement {
    sid    = "GlueCatalogRead"
    effect = "Allow"

    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]

    resources = [
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:catalog",
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:database/${aws_glue_catalog_database.cur.name}",
      "arn:${local.partition}:glue:${local.region}:${local.account_id}:table/${aws_glue_catalog_database.cur.name}/*",
    ]
  }

  # S3 — read CUR Parquet files (no delete, no overwrite, no cross-bucket).
  statement {
    sid    = "S3CurRead"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*",
    ]
  }

  # S3 — write Athena query results to the dedicated results bucket only.
  statement {
    sid    = "S3AthenaResultsWrite"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/*",
    ]
  }
}
