locals {
  account_name   = "log-archive"
  account_id     = "888888888888" # TODO: Replace with actual AWS log-archive account ID
  aws_account_id = "888888888888"
  environment    = "log-archive"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-log-archive"

  # Organization context
  org_account_type   = "log-archive"
  org_ou             = "Security"
  management_account = "000000000000"

  email = "aws+log-archive@example.com"

  # Centralized log-archive bucket lives here. Other accounts ship CloudTrail,
  # Config snapshots, VPC Flow Logs, EKS audit/authenticator (see #178, #182)
  # to this bucket via cross-account write policies.
  primary_region = "eu-west-1"

  # Object Lock + KMS + replication enforced via _envcommon/centralized-logging.hcl.
  log_archive_bucket_name = "platform-log-archive-888888888888-eu-west-1"

  enable_eks = false
  enable_rds = false
}
