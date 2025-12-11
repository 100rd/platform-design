resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.secrets

  name        = each.key
  description = each.value
  tags        = var.tags
}

# We don't create secret versions here as they contain sensitive data.
# They should be populated manually or via a secure pipeline.
