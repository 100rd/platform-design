# ---------------------------------------------------------------------------------------------------------------------
# Auto-Shutdown — Dev Cost Controls
# ---------------------------------------------------------------------------------------------------------------------
# Stops and starts EC2 instances on a business-hours schedule via EventBridge Scheduler
# and a Python Lambda function. Only affects instances tagged:
#   Environment = development
#   AutoShutdown = true
#
# Schedules (UTC, configurable):
#   Shutdown — Mon-Fri 19:00 UTC
#   Startup  — Mon-Fri 07:30 UTC
#
# Set enabled = false to skip all resource creation in non-dev environments.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Lambda source: inline Python packaged with archive_file
# ---------------------------------------------------------------------------

data "archive_file" "auto_shutdown" {
  count = var.enabled ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda_auto_shutdown.zip"

  source {
    filename = "handler.py"
    content  = <<-PYTHON
      """
      Auto-shutdown/startup Lambda for dev EC2 instances.

      Triggered by EventBridge Scheduler with a JSON event payload:
        {"action": "stop"}   -- shutdown schedule
        {"action": "start"}  -- startup schedule

      Only affects instances tagged:
        Environment = development
        AutoShutdown = true
      """
      import boto3
      import logging

      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      FILTER_TAGS = [
          {"Name": "tag:Environment", "Values": ["development"]},
          {"Name": "tag:AutoShutdown", "Values": ["true"]},
      ]


      def lambda_handler(event, context):
          action = event.get("action", "").lower()
          if action not in ("stop", "start"):
              raise ValueError(f"Unknown action '{action}'. Expected 'stop' or 'start'.")

          ec2 = boto3.client("ec2")
          paginator = ec2.get_paginator("describe_instances")
          instance_ids = []

          for page in paginator.paginate(Filters=FILTER_TAGS):
              for reservation in page["Reservations"]:
                  for instance in reservation["Instances"]:
                      state = instance["State"]["Name"]
                      iid = instance["InstanceId"]
                      # For stop: target running instances
                      # For start: target stopped instances
                      if action == "stop" and state == "running":
                          instance_ids.append(iid)
                      elif action == "start" and state == "stopped":
                          instance_ids.append(iid)

          if not instance_ids:
              logger.info("No instances to %s.", action)
              return {"action": action, "affected": []}

          logger.info("%sing %d instance(s): %s", action.capitalize(), len(instance_ids), instance_ids)

          if action == "stop":
              ec2.stop_instances(InstanceIds=instance_ids)
          else:
              ec2.start_instances(InstanceIds=instance_ids)

          logger.info("Done.")
          return {"action": action, "affected": instance_ids}
    PYTHON
  }
}

# ---------------------------------------------------------------------------
# IAM role for Lambda — least-privilege, tag-conditioned
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  count = var.enabled ? 1 : 0

  statement {
    sid     = "LambdaAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "auto_shutdown_lambda" {
  count = var.enabled ? 1 : 0

  name               = "${var.project}-${var.environment}-auto-shutdown-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role[0].json
  description        = "Role for the dev auto-shutdown Lambda function"

  tags = var.tags
}

data "aws_iam_policy_document" "auto_shutdown_lambda" {
  count = var.enabled ? 1 : 0

  # CloudWatch Logs
  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-${var.environment}-auto-shutdown:*",
    ]
  }

  # EC2 describe — no tag condition needed (read-only, cannot change state)
  statement {
    sid       = "EC2Describe"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # EC2 stop/start — restricted to instances tagged Environment=development
  statement {
    sid = "EC2StopStart"
    actions = [
      "ec2:StopInstances",
      "ec2:StartInstances",
    ]
    resources = ["arn:aws:ec2:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Environment"
      values   = ["development"]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/AutoShutdown"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "auto_shutdown_lambda" {
  count = var.enabled ? 1 : 0

  name   = "${var.project}-${var.environment}-auto-shutdown-lambda"
  role   = aws_iam_role.auto_shutdown_lambda[0].id
  policy = data.aws_iam_policy_document.auto_shutdown_lambda[0].json
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group (explicit — for retention + encryption control)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "auto_shutdown" {
  count = var.enabled ? 1 : 0

  name              = "/aws/lambda/${var.project}-${var.environment}-auto-shutdown"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "auto_shutdown" {
  count = var.enabled ? 1 : 0

  function_name = "${var.project}-${var.environment}-auto-shutdown"
  description   = "Stops/starts dev EC2 instances tagged AutoShutdown=true on a schedule"
  role          = aws_iam_role.auto_shutdown_lambda[0].arn

  filename         = data.archive_file.auto_shutdown[0].output_path
  source_code_hash = data.archive_file.auto_shutdown[0].output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  timeout          = 60
  memory_size      = 128

  # Reserve -1 means unreserved (uses account concurrency pool).
  # This low-frequency scheduler function does not need reserved concurrency.
  reserved_concurrent_executions = -1

  tracing_config {
    mode = "PassThrough"
  }

  tags = var.tags

  depends_on = [
    aws_cloudwatch_log_group.auto_shutdown,
    aws_iam_role_policy.auto_shutdown_lambda,
  ]
}

# ---------------------------------------------------------------------------
# IAM role for EventBridge Scheduler to invoke Lambda
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "scheduler_assume_role" {
  count = var.enabled ? 1 : 0

  statement {
    sid     = "SchedulerAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count = var.enabled ? 1 : 0

  name               = "${var.project}-${var.environment}-auto-shutdown-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role[0].json
  description        = "Role for EventBridge Scheduler to invoke the auto-shutdown Lambda"

  tags = var.tags
}

data "aws_iam_policy_document" "scheduler_invoke_lambda" {
  count = var.enabled ? 1 : 0

  statement {
    sid       = "InvokeLambda"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.auto_shutdown[0].arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  count = var.enabled ? 1 : 0

  name   = "${var.project}-${var.environment}-auto-shutdown-invoke-lambda"
  role   = aws_iam_role.scheduler[0].id
  policy = data.aws_iam_policy_document.scheduler_invoke_lambda[0].json
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler — Shutdown (Mon-Fri 19:00 UTC)
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule" "shutdown" {
  count = var.enabled ? 1 : 0

  name        = "${var.project}-${var.environment}-shutdown"
  description = "Stop dev EC2 instances tagged AutoShutdown=true — Mon-Fri 19:00 UTC"
  group_name  = "default"

  schedule_expression          = var.shutdown_schedule
  schedule_expression_timezone = var.timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.auto_shutdown[0].arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ action = "stop" })
  }
}

# ---------------------------------------------------------------------------
# EventBridge Scheduler — Startup (Mon-Fri 07:30 UTC)
# ---------------------------------------------------------------------------

resource "aws_scheduler_schedule" "startup" {
  count = var.enabled ? 1 : 0

  name        = "${var.project}-${var.environment}-startup"
  description = "Start dev EC2 instances tagged AutoShutdown=true — Mon-Fri 07:30 UTC"
  group_name  = "default"

  schedule_expression          = var.startup_schedule
  schedule_expression_timezone = var.timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.auto_shutdown[0].arn
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ action = "start" })
  }
}
