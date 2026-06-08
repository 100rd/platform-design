locals {
  account_name   = "security"
  account_id     = "777777777777" # TODO: Replace with actual AWS security account ID
  aws_account_id = "777777777777"
  environment    = "security"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-security"

  # Organization context
  org_account_type   = "security"
  org_ou             = "Security"
  management_account = "000000000000"

  # Email used at account-vending time. Maps to AWS-account root email.
  email = "aws+security@example.com"

  # Security tooling delegated-admin in this account:
  #   - GuardDuty (delegated from management)
  #   - SecurityHub (delegated from management)
  #   - Detective, Inspector, Macie (when enabled)
  # Cross-region aggregation home region:
  primary_region = "eu-west-1"

  # Sizing — security tooling is light on infra: no EKS, no RDS by default.
  enable_eks = false
  enable_rds = false
}
