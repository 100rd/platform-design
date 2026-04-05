output "policy_ids" {
  description = "Map of SCP name to policy ID"
  value = {
    deny_leave_org          = aws_organizations_policy.deny_leave_org.id
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail.id
    deny_root_account       = aws_organizations_policy.deny_root_account.id
    restrict_regions        = aws_organizations_policy.restrict_regions.id
    deny_guardduty_changes  = aws_organizations_policy.deny_guardduty_changes.id
    deny_s3_public          = aws_organizations_policy.deny_s3_public.id
    require_ebs_encryption  = aws_organizations_policy.require_ebs_encryption.id
    deny_all_suspended      = aws_organizations_policy.deny_all_suspended.id
  }
}

output "policy_arns" {
  description = "Map of SCP name to policy ARN"
  value = {
    deny_leave_org          = aws_organizations_policy.deny_leave_org.arn
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail.arn
    deny_root_account       = aws_organizations_policy.deny_root_account.arn
    restrict_regions        = aws_organizations_policy.restrict_regions.arn
    deny_guardduty_changes  = aws_organizations_policy.deny_guardduty_changes.arn
    deny_s3_public          = aws_organizations_policy.deny_s3_public.arn
    require_ebs_encryption  = aws_organizations_policy.require_ebs_encryption.arn
    deny_all_suspended      = aws_organizations_policy.deny_all_suspended.arn
  }
}
