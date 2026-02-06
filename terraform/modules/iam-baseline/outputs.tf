# ---------------------------------------------------------------------------------------------------------------------
# IAM Baseline Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "password_policy" {
  description = "Summary of the account password policy settings for audit documentation"
  value = {
    minimum_password_length        = aws_iam_account_password_policy.pci_dss.minimum_password_length
    require_lowercase_characters   = aws_iam_account_password_policy.pci_dss.require_lowercase_characters
    require_uppercase_characters   = aws_iam_account_password_policy.pci_dss.require_uppercase_characters
    require_numbers                = aws_iam_account_password_policy.pci_dss.require_numbers
    require_symbols                = aws_iam_account_password_policy.pci_dss.require_symbols
    max_password_age               = aws_iam_account_password_policy.pci_dss.max_password_age
    password_reuse_prevention      = aws_iam_account_password_policy.pci_dss.password_reuse_prevention
    allow_users_to_change_password = aws_iam_account_password_policy.pci_dss.allow_users_to_change_password
    hard_expiry                    = aws_iam_account_password_policy.pci_dss.hard_expiry
  }
}

output "enforce_mfa_policy_arn" {
  description = "ARN of the MFA enforcement IAM policy — attach to break-glass user groups"
  value       = aws_iam_policy.enforce_mfa.arn
}

output "enforce_mfa_policy_name" {
  description = "Name of the MFA enforcement IAM policy"
  value       = aws_iam_policy.enforce_mfa.name
}
