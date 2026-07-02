# -----------------------------------------------------------------------------
# ESO IRSA — IAM Role for External Secrets Operator
# Binds the external-secrets Kubernetes service account to an IAM role
# via IRSA (IAM Roles for Service Accounts), granting read access to
# Secrets Manager and KMS decrypt for envelope encryption.
# Issue #39
# -----------------------------------------------------------------------------

module "eso_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name = "${var.project}-${var.environment}-eso"

  # Bind to the external-secrets service account in the external-secrets namespace
  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets_manager = aws_iam_policy.eso_secrets_manager.arn
  }

  tags = var.tags
}

resource "aws_iam_policy" "eso_secrets_manager" {
  name        = "${var.project}-${var.environment}-eso-secrets-manager"
  description = "Allow External Secrets Operator to read secrets from Secrets Manager and decrypt with KMS"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
        ]
        Resource = var.secrets_arns_prefix != "" ? [
          "${var.secrets_arns_prefix}/${var.project}/*",
        ] : ["arn:aws:secretsmanager:*:*:secret:${var.project}/*"]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = var.kms_key_arns
      },
    ]
  })

  tags = var.tags
}
