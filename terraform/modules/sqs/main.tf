resource "aws_sqs_queue" "this" {
  name = var.name

  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds
  max_message_size            = var.max_message_size
  delay_seconds               = var.delay_seconds
  receive_wait_time_seconds   = var.receive_wait_time_seconds
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null

  sqs_managed_sse_enabled = true

  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = var.tags
}

resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name = var.fifo_queue ? "${var.name}-dlq.fifo" : "${var.name}-dlq"

  message_retention_seconds = var.dlq_message_retention_seconds
  fifo_queue                = var.fifo_queue
  sqs_managed_sse_enabled   = true

  tags = var.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

# IAM policy for IRSA access
data "aws_iam_policy_document" "producer" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.this.arn]
  }
}

data "aws_iam_policy_document" "consumer" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.this.arn]
  }
}

resource "aws_iam_policy" "producer" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.name}-sqs-producer"
  policy = data.aws_iam_policy_document.producer.json

  tags = var.tags
}

resource "aws_iam_policy" "consumer" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.name}-sqs-consumer"
  policy = data.aws_iam_policy_document.consumer.json

  tags = var.tags
}
