# ---------------------------------------------------------------------------------------------------------------------
# EKS Audit + Authenticator Log Aggregation
# ---------------------------------------------------------------------------------------------------------------------
# Routes EKS control-plane log streams (audit, authenticator) from the
# per-cluster CloudWatch log group to the centralized log-archive bucket
# in the log-archive account, via a Kinesis Firehose delivery stream.
#
# This is the workload-account-side complement of the log-archive bucket
# created by terraform/modules/centralized-logging (#182). Each EKS
# cluster instantiates this module once.
#
# Issue #178.
# ---------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Source CloudWatch log group — managed by EKS itself, but we set retention
# centrally so it doesn't drift to "Never expire".
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_group_retention_days
  tags              = var.tags

  # EKS creates this group lazily on first write; importing an existing
  # group is the typical onboarding path. Once imported, retention is
  # managed here.
  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Firehose delivery stream — CloudWatch Logs subscription -> S3 (log-archive)
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${var.cluster_name}-eks-log-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "firehose" {
  # Firehose writes objects to the cross-account log-archive bucket.
  statement {
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]
    resources = [
      var.destination_s3_bucket_arn,
      "${var.destination_s3_bucket_arn}/*",
    ]
  }

  # Encrypt with the destination bucket's KMS key.
  statement {
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [var.destination_kms_key_arn]
  }

  # CloudWatch Logs error stream for Firehose.
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${var.cluster_name}-eks-log-firehose"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  name        = "${var.cluster_name}-eks-control-plane-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.destination_s3_bucket_arn
    prefix              = "${var.destination_s3_prefix}/AWSLogs/!{partitionKeyFromQuery:account_id}/${var.aws_region}/${var.cluster_name}/"
    error_output_prefix = "${var.destination_s3_prefix}-errors/"

    buffering_interval = var.firehose_buffer_seconds
    buffering_size     = var.firehose_buffer_size_mb

    compression_format = "GZIP"

    kms_key_arn = var.destination_kms_key_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = "/aws/kinesisfirehose/${var.cluster_name}-eks-logs"
      log_stream_name = "S3Delivery"
    }

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true

      processors {
        type = "MetadataExtraction"

        parameters {
          parameter_name  = "MetadataExtractionQuery"
          parameter_value = "{account_id: .userIdentity.accountId}"
        }

        parameters {
          parameter_name  = "JsonParsingEngine"
          parameter_value = "JQ-1.6"
        }
      }
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Logs subscription filter — fan-in from each forwarded stream
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "subscription_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "subscription" {
  name               = "${var.cluster_name}-eks-log-subscription"
  assume_role_policy = data.aws_iam_policy_document.subscription_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "subscription" {
  statement {
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
    ]
    resources = [aws_kinesis_firehose_delivery_stream.this.arn]
  }
}

resource "aws_iam_role_policy" "subscription" {
  name   = "${var.cluster_name}-eks-log-subscription"
  role   = aws_iam_role.subscription.id
  policy = data.aws_iam_policy_document.subscription.json
}

# Subscription filter: one per stream we forward (audit, authenticator).
# CloudWatch's filter pattern '' matches every record on the stream.
resource "aws_cloudwatch_log_subscription_filter" "this" {
  for_each = toset(var.log_streams_to_forward)

  name            = "${var.cluster_name}-${each.value}-to-firehose"
  log_group_name  = aws_cloudwatch_log_group.cluster.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.this.arn
  role_arn        = aws_iam_role.subscription.arn
  distribution    = "ByLogStream"
}
