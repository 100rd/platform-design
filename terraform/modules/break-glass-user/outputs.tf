# ---------------------------------------------------------------------------------------------------------------------
# Break-glass User Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "user_name" {
  description = "Name of the break-glass IAM user."
  value       = aws_iam_user.this.name
}

output "user_arn" {
  description = "ARN of the break-glass IAM user."
  value       = aws_iam_user.this.arn
}

output "mfa_serial" {
  description = <<-EOT
    Expected MFA device ARN once the user enrolls a virtual MFA token. The actual
    MFA serial is created by the operator on first login (the user is allowed to
    create its own virtual MFA device). Used as a hint in the break-glass runbook.
  EOT
  value       = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:mfa/${aws_iam_user.this.name}"
}

output "access_key_id" {
  description = "Access key ID for the break-glass user. Copy into the team password manager on first apply. Null when create_access_key = false."
  value       = try(aws_iam_access_key.this[0].id, null)
}

output "access_key_secret" {
  description = "Secret for the break-glass user's access key. SENSITIVE. Copy into the team password manager on first apply, then rotate. Null when create_access_key = false."
  value       = try(aws_iam_access_key.this[0].secret, null)
  sensitive   = true
}

output "console_password" {
  description = "Initial console password (reset required on first login). SENSITIVE. Null when create_console_login = false."
  value       = try(aws_iam_user_login_profile.this[0].password, null)
  sensitive   = true
}

output "alarm_arn" {
  description = "ARN of the CloudWatch alarm that fires on break-glass usage. Null if the alarm chain was disabled (cloudtrail_log_group_name or alarm_sns_topic_arn unset)."
  value       = try(aws_cloudwatch_metric_alarm.usage[0].arn, null)
}
