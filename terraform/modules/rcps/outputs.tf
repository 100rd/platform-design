output "policy_ids" {
  description = "Map of RCP name to policy ID"
  value = {
    org_perimeter = aws_organizations_policy.org_perimeter.id
  }
}

output "policy_arns" {
  description = "Map of RCP name to policy ARN"
  value = {
    org_perimeter = aws_organizations_policy.org_perimeter.arn
  }
}

output "attached_target_ids" {
  description = "OU/root IDs the org-perimeter RCP is attached to (the staged-rollout targets)"
  value       = [for a in aws_organizations_policy_attachment.org_perimeter : a.target_id]
}
