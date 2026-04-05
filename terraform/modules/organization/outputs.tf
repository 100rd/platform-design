output "organization_id" {
  description = "The ID of the AWS Organization"
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "The ARN of the AWS Organization"
  value       = aws_organizations_organization.this.arn
}

output "master_account_id" {
  description = "The master account ID"
  value       = aws_organizations_organization.this.master_account_id
}

output "roots" {
  description = "Organization root details"
  value       = aws_organizations_organization.this.roots
}

output "root_id" {
  description = "The ID of the organization root — use this for root-level SCP attachments"
  value       = aws_organizations_organization.this.roots[0].id
}

output "ou_ids" {
  description = "Map of OU name to OU ID (includes Root, all top-level, and nested OUs)"
  value = merge(
    { "Root" = aws_organizations_organization.this.roots[0].id },
    { for k, v in aws_organizations_organizational_unit.top_level : k => v.id },
    { for k, v in aws_organizations_organizational_unit.nested : k => v.id },
  )
}

output "suspended_ou_id" {
  description = "The ID of the Suspended/Quarantine OU — wire this into the scps module's suspended_ou_id input to attach the deny-all SCP"
  value       = aws_organizations_organizational_unit.suspended.id
}

output "account_ids" {
  description = "Map of account name to account ID"
  value       = { for k, v in aws_organizations_account.members : k => v.id }
}
