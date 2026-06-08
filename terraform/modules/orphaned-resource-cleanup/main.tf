# ---------------------------------------------------------------------------------------------------------------------
# Orphaned Resource Detection (advisory-only)
# ---------------------------------------------------------------------------------------------------------------------
# A scheduled Lambda (EventBridge cron) that scans the configured AWS
# regions for "orphaned" resources — unattached EBS volumes, unused EIPs,
# 'available' ENIs, old EBS snapshots, idle NAT gateways, unattached
# load balancers — and posts a JSON report to S3 plus an optional SNS
# summary.
#
# IMPORTANT: this module is ADVISORY ONLY. It never deletes anything.
# See issue #181 acceptance criteria.
# ---------------------------------------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM role for the scanner Lambda. Read-only across all configured services.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scanner" {
  name               = "${var.name_prefix}-orphaned-scanner"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.scanner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Read-only EC2 + ELB scanning permissions, plus narrow S3 PutObject
# scoped to the report prefix and optional SNS Publish to the configured
# topic.
data "aws_iam_policy_document" "scanner" {
  # Read-only scanning. Any new check must extend this list.
  statement {
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeAddresses",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSnapshots",
      "ec2:DescribeNatGateways",
      "ec2:DescribeRegions",
      "ec2:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeListeners",
    ]
    resources = ["*"]
  }

  # Write the report to the log-archive bucket prefix only.
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.report_s3_bucket}/${var.report_s3_prefix}/*"]
  }

  # Optional SNS publish for Slack relay.
  dynamic "statement" {
    for_each = var.slack_sns_topic_arn != "" ? [1] : []
    content {
      actions   = ["sns:Publish"]
      resources = [var.slack_sns_topic_arn]
    }
  }
}

resource "aws_iam_role_policy" "scanner" {
  name   = "${var.name_prefix}-orphaned-scanner"
  role   = aws_iam_role.scanner.id
  policy = data.aws_iam_policy_document.scanner.json
}

# -----------------------------------------------------------------------------
# Lambda function: ships pre-packaged Python source from sibling lambda/ dir.
# The packaging step keeps the module self-contained — no external build.
# -----------------------------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.terraform-lambda.zip"
}

resource "aws_lambda_function" "scanner" {
  function_name    = "${var.name_prefix}-orphaned-scanner"
  role             = aws_iam_role.scanner.arn
  runtime          = "python3.12"
  handler          = "scanner.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = var.lambda_memory_mb
  timeout          = var.lambda_timeout_seconds

  environment {
    variables = {
      REPORT_S3_BUCKET          = var.report_s3_bucket
      REPORT_S3_PREFIX          = var.report_s3_prefix
      SLACK_SNS_TOPIC_ARN       = var.slack_sns_topic_arn
      REGIONS_TO_SCAN           = join(",", var.regions_to_scan)
      EBS_VOLUME_MIN_AGE_DAYS   = tostring(var.ebs_volume_min_age_days)
      EBS_SNAPSHOT_MAX_AGE_DAYS = tostring(var.ebs_snapshot_max_age_days)
      CHECK_UNATTACHED_EBS      = tostring(coalesce(var.checks_enabled.unattached_ebs_volumes, true))
      CHECK_UNUSED_EIPS         = tostring(coalesce(var.checks_enabled.unused_elastic_ips, true))
      CHECK_AVAILABLE_ENIS      = tostring(coalesce(var.checks_enabled.available_enis, true))
      CHECK_OLD_SNAPSHOTS       = tostring(coalesce(var.checks_enabled.old_ebs_snapshots, true))
      CHECK_IDLE_NAT_GATEWAYS   = tostring(coalesce(var.checks_enabled.idle_nat_gateways, true))
      CHECK_UNATTACHED_LBS      = tostring(coalesce(var.checks_enabled.unattached_load_balancers, true))
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EventBridge schedule -> Lambda
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name_prefix}-orphaned-scanner-schedule"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.scanner.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scanner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
