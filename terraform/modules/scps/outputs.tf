output "policy_ids" {
  description = "Map of SCP name to policy ID"
  value = {
    deny_leave_org        = aws_organizations_policy.deny_leave_org.id
    deny_disable_cloudtrail = aws_organizations_policy.deny_disable_cloudtrail.id
    deny_root_account     = aws_organizations_policy.deny_root_account.id
    restrict_regions      = aws_organizations_policy.restrict_regions.id
    deny_public_s3_prod   = aws_organizations_policy.deny_public_s3_prod.id
  }
}
