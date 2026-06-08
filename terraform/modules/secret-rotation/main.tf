# ---------------------------------------------------------------------------------------------------------------------
# secret-rotation (ADR-0031)
# ---------------------------------------------------------------------------------------------------------------------
# Self-contained automated rotation of a single DB/API credential:
#   - aws_secretsmanager_secret           (KMS-encrypted credential store)
#   - aws_secretsmanager_secret_rotation  (schedule via rotation_rules)
#   - aws_lambda_function                 (rotation function: placeholder OR an
#                                          AWS-provided RDS rotation template)
#   - least-privilege IAM                 (scoped to THIS secret ARN + its CMK)
#   - vpc_config                          (so the Lambda can reach a private RDS)
#
# Complements modules/secrets, which only wires rotation IF handed a Lambda ARN.
# This module PRODUCES that Lambda + plumbing.
# ---------------------------------------------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  # Secret names allow "/" (path-style), but IAM role / Lambda / log-group names do
  # not. Derive a safe slug for those resources by replacing "/" with "-".
  name_slug = replace(var.name, "/", "-")

  lambda_function_name = "${local.name_slug}-rotation"
  role_name            = "${local.name_slug}-rotation-role"
  log_group_name       = "/aws/lambda/${local.name_slug}-rotation"

  # Use a prebuilt package (e.g. an AWS RDS rotation template) when provided,
  # otherwise package the bundled placeholder handler.
  use_prebuilt_package = var.lambda_package_path != null
  enable_vpc_config    = length(var.vpc_subnet_ids) > 0
}

# ---------------------------------------------------------------------------------------------------------------------
# Secret (KMS-encrypted). Values are NOT created here — they are populated by the
# rotation Lambda or a secure pipeline (mirrors modules/secrets).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.secret_description
  kms_key_id  = var.kms_key_arn

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# Rotation Lambda package (placeholder) — only built when no prebuilt package given.
# ---------------------------------------------------------------------------------------------------------------------

data "archive_file" "placeholder" {
  count = local.use_prebuilt_package ? 0 : 1

  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/${local.name_slug}-rotation.zip"
}

# ---------------------------------------------------------------------------------------------------------------------
# IAM — least-privilege execution role for the rotation Lambda (ADR-0031).
#   - secretsmanager:*  scoped to THIS secret ARN only
#   - kms:Decrypt / GenerateDataKey scoped to THIS secret's CMK
#   - CloudWatch Logs for the function's own log group
#   - AWSLambdaVPCAccessExecutionRole only when VPC config is enabled (ENI mgmt)
# ---------------------------------------------------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = var.tags
}

data "aws_iam_policy_document" "rotation" {
  # Secrets Manager — scoped to THIS secret ARN only (least privilege).
  statement {
    sid    = "RotateThisSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]

    resources = [aws_secretsmanager_secret.this.arn]
  }

  # GetRandomPassword has no resource scope (it generates, not reads a secret).
  statement {
    sid       = "GenerateNewPassword"
    effect    = "Allow"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  # KMS — scoped to the secret's CMK only.
  statement {
    sid    = "DecryptWithSecretCmk"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [var.kms_key_arn]
  }

  # CloudWatch Logs — scoped to the function's own log group.
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}:*",
    ]
  }
}

resource "aws_iam_role_policy" "rotation" {
  name   = "${local.name_slug}-rotation-policy"
  role   = aws_iam_role.rotation.id
  policy = data.aws_iam_policy_document.rotation.json
}

# ENI management for VPC-attached Lambdas. Only attached when VPC config is on.
resource "aws_iam_role_policy_attachment" "vpc_access" {
  count = local.enable_vpc_config ? 1 : 0

  role       = aws_iam_role.rotation.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ---------------------------------------------------------------------------------------------------------------------
# Log group (explicit, so retention is enforced rather than never-expire default).
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rotation" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# Rotation Lambda.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_lambda_function" "rotation" {
  function_name = local.lambda_function_name
  role          = aws_iam_role.rotation.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = local.use_prebuilt_package ? var.lambda_package_path : data.archive_file.placeholder[0].output_path
  source_code_hash = local.use_prebuilt_package ? filebase64sha256(var.lambda_package_path) : data.archive_file.placeholder[0].output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  # Encrypt the env-var payload with the secret's CMK rather than the AWS-owned key.
  kms_key_arn = var.kms_key_arn

  environment {
    variables = merge(
      {
        SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${local.region}.amazonaws.com"
      },
      var.lambda_environment_variables,
    )
  }

  dynamic "vpc_config" {
    for_each = local.enable_vpc_config ? [1] : []

    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.rotation,
    aws_cloudwatch_log_group.rotation,
  ]
}

# Allow Secrets Manager to invoke the rotation function.
resource "aws_lambda_permission" "secretsmanager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.this.arn
}

# ---------------------------------------------------------------------------------------------------------------------
# Rotation schedule (rotation_rules). Provide automatically_after_days OR a
# schedule_expression — the provider requires exactly one. duration is optional.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_secretsmanager_secret_rotation" "this" {
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  rotate_immediately  = var.rotate_immediately

  rotation_rules {
    automatically_after_days = var.rotation_schedule_expression == null ? var.rotation_after_days : null
    schedule_expression      = var.rotation_schedule_expression
    duration                 = var.rotation_duration
  }

  depends_on = [aws_lambda_permission.secretsmanager]
}
