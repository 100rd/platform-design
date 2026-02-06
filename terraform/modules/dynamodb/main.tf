# ---------------------------------------------------------------------------------------------------------------------
# DynamoDB Table
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a DynamoDB table with optional GSIs, PITR, TTL, server-side encryption,
# and IRSA IAM policies (readwrite + readonly) for EKS workloads.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = lookup(global_secondary_index.value, "range_key", null)
      projection_type = lookup(global_secondary_index.value, "projection_type", "ALL")
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  ttl {
    attribute_name = var.ttl_attribute
    enabled        = var.ttl_attribute != ""
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM Policies for IRSA access
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "readwrite" {
  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:BatchGetItem",
    ]
    resources = [
      aws_dynamodb_table.this.arn,
      "${aws_dynamodb_table.this.arn}/index/*",
    ]
  }
}

data "aws_iam_policy_document" "readonly" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchGetItem",
    ]
    resources = [
      aws_dynamodb_table.this.arn,
      "${aws_dynamodb_table.this.arn}/index/*",
    ]
  }
}

resource "aws_iam_policy" "readwrite" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.name}-dynamodb-readwrite"
  policy = data.aws_iam_policy_document.readwrite.json

  tags = var.tags
}

resource "aws_iam_policy" "readonly" {
  count = var.create_iam_policies ? 1 : 0

  name   = "${var.name}-dynamodb-readonly"
  policy = data.aws_iam_policy_document.readonly.json

  tags = var.tags
}
