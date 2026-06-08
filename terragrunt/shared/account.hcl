locals {
  account_name   = "shared"
  account_id     = "999999999999" # TODO: Replace with actual AWS shared-services account ID
  aws_account_id = "999999999999"
  environment    = "shared"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-shared"

  # Organization context
  org_account_type   = "shared-services"
  org_ou             = "Infrastructure"
  management_account = "000000000000"

  email = "aws+shared@example.com"

  # Shared services hosted here:
  #   - ECR registry (replicated to workload regions)
  #   - Route53 private hosted zones (delegated to spokes via association)
  #   - ACM certificate central authority (where DNS-01 challenge anchors)
  #   - Service Catalog portfolios for self-service vending
  primary_region = "eu-west-1"

  # Lightweight footprint — no EKS, optional small RDS for tooling state.
  enable_eks = false
  enable_rds = false
}
