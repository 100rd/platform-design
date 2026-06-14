output "policy_id" {
  description = "ID of the EC2 declarative policy."
  value       = aws_organizations_policy.ec2.id
}

output "policy_arn" {
  description = "ARN of the EC2 declarative policy."
  value       = aws_organizations_policy.ec2.arn
}

output "attached_target_ids" {
  description = "OU/root IDs the EC2 declarative policy is attached to (staged-rollout targets)."
  value       = [for a in aws_organizations_policy_attachment.ec2 : a.target_id]
}
