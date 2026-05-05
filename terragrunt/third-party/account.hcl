locals {
  account_name   = "third-party"
  account_id     = "121212121212" # TODO: Replace with actual AWS third-party-integrations account ID
  aws_account_id = "121212121212"
  environment    = "third-party"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-third-party"

  # Organization context. Lives in a dedicated OU so SCPs can grant
  # narrow cross-org trust to vendor IAM principals (Datadog, Vanta,
  # Snyk, etc.) without polluting workload accounts.
  org_account_type   = "third-party-integrations"
  org_ou             = "Security"
  management_account = "000000000000"

  email = "aws+third-party@example.com"

  primary_region = "eu-west-1"

  # No EKS / RDS — this account holds IAM roles + cross-account audit
  # exports only.
  enable_eks = false
  enable_rds = false
}
