# ---------------------------------------------------------------------------------------------------------------------
# EventBridge S3-to-SQS Rule
# ---------------------------------------------------------------------------------------------------------------------
# Routes S3 ObjectCreated events for specific file suffixes to an SQS queue.
# Requires EventBridge notifications to be enabled on the source S3 bucket.
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Enable EventBridge notifications on the source S3 bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_notification" "this" {
  bucket      = var.source_bucket_name
  eventbridge = true
}

# ---------------------------------------------------------------------------
# EventBridge rule — match S3 Object Created events for video files
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "this" {
  name        = var.name
  description = "Route S3 ObjectCreated events from ${var.source_bucket_name} to SQS"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.source_bucket_name]
      }
      object = {
        key = [for suffix in var.event_pattern_suffix : { suffix = suffix }]
      }
    }
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# EventBridge target — send matching events to SQS
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "this" {
  rule = aws_cloudwatch_event_rule.this.name
  arn  = var.target_queue_arn

  # Use the full event detail as the SQS message body
  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name"
      key    = "$.detail.object.key"
      size   = "$.detail.object.size"
      etag   = "$.detail.object.etag"
    }
    input_template = <<-TEMPLATE
      {
        "bucket": <bucket>,
        "key": <key>,
        "size": <size>,
        "etag": <etag>,
        "source": "eventbridge"
      }
    TEMPLATE
  }
}

# ---------------------------------------------------------------------------
# SQS queue policy — allow EventBridge to send messages
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "sqs_allow_eventbridge" {
  statement {
    sid    = "AllowEventBridgeSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [var.target_queue_arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.this.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = var.target_queue_url
  policy    = data.aws_iam_policy_document.sqs_allow_eventbridge.json
}
