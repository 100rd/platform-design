output "keys" {
  description = "Map of key alias suffix to key details (key_arn, key_id, alias_arn)"
  value = {
    for k, v in aws_kms_key.this : k => {
      key_arn   = v.arn
      key_id    = v.key_id
      alias_arn = aws_kms_alias.this[k].arn
    }
  }
}

output "key_arns" {
  description = "Map of key alias suffix to KMS key ARN"
  value       = { for k, v in aws_kms_key.this : k => v.arn }
}

output "key_ids" {
  description = "Map of key alias suffix to KMS key ID"
  value       = { for k, v in aws_kms_key.this : k => v.key_id }
}
