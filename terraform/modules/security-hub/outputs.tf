output "hub_arn" {
  description = "ARN of the Security Hub account resource"
  value       = aws_securityhub_account.this.arn
}

output "hub_id" {
  description = "ID of the Security Hub account resource"
  value       = aws_securityhub_account.this.id
}

output "pci_dss_subscription_arn" {
  description = "ARN of the PCI-DSS standards subscription (null if disabled)"
  value       = var.enable_pci_dss_standard ? aws_securityhub_standards_subscription.pci_dss[0].id : null
}

output "cis_subscription_arn" {
  description = "ARN of the CIS Foundations standards subscription (null if disabled)"
  value       = var.enable_cis_standard ? aws_securityhub_standards_subscription.cis[0].id : null
}
