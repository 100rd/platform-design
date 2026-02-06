output "detector_id" {
  description = "The ID of the GuardDuty detector"
  value       = aws_guardduty_detector.this.id
}

output "detector_arn" {
  description = "The ARN of the GuardDuty detector"
  value       = aws_guardduty_detector.this.arn
}

output "admin_account_id" {
  description = "The account ID delegated as GuardDuty administrator"
  value       = local.admin_account_id
}
