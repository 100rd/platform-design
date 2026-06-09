locals {
  account_name   = "management"
  account_id     = "000000000000" # TODO: Replace with actual AWS management account ID
  aws_account_id = "000000000000"
  environment    = "management"
  email          = "aws+management@example.com"

  # Cost allocation and audit tracing
  owner       = "platform-team"
  cost_center = "platform-infra"

  # Organization context
  org_account_type = "management"
  org_ou           = "Root"

  # Organization structure
  organization_name = "platform-org"
  organization_id   = "" # Populated after org creation

  # Member accounts
  # Account-to-OU placement is managed here (see docs/ou-structure.md). Account IDs
  # mirror each account's own terragrunt/<name>/account.hcl — keep them in sync.
  member_accounts = {
    # Infrastructure OU — shared platform tooling (networking hub, shared services)
    network = {
      account_id = "555555555555"
      email      = "aws+network@example.com"
      ou         = "Infrastructure"
    }
    shared = {
      account_id = "999999999999"
      email      = "aws+shared@example.com"
      ou         = "Infrastructure"
    }
    # Security OU — audit and security-tooling accounts
    security = {
      account_id = "777777777777"
      email      = "aws+security@example.com"
      ou         = "Security"
    }
    "log-archive" = {
      account_id = "888888888888"
      email      = "aws+log-archive@example.com"
      ou         = "Security"
    }
    "third-party" = {
      account_id = "121212121212"
      email      = "aws+third-party@example.com"
      ou         = "Security"
    }
    # Workloads/NonProd OU — non-production workload accounts
    dev = {
      account_id = "111111111111"
      email      = "aws+dev@example.com"
      ou         = "NonProd"
    }
    staging = {
      account_id = "222222222222"
      email      = "aws+staging@example.com"
      ou         = "NonProd"
    }
    # Workloads/Prod OU — production workload accounts
    prod = {
      account_id = "333333333333"
      email      = "aws+prod@example.com"
      ou         = "Prod"
    }
    dr = {
      account_id = "444444444444"
      email      = "aws+dr@example.com"
      ou         = "Prod"
    }
  }

  # Network account reference
  network_account_id = "555555555555"

  # ---------------------------------------------------------------------------
  # Admin / operator CIDR allow-list (ADR-0010)
  # Org-level reference for the trusted source ranges allowed to reach an EKS
  # *public* API endpoint in restricted (prod-tier) environments. Each workload
  # account composes its own narrow allow-list from these ranges in its own
  # account.hcl instead of falling back to 0.0.0.0/0.
  #
  # TODO: replace the placeholder corp range below with the real office / VPN
  # egress CIDRs (and any CI runner ranges) before enabling prod public access.
  admin_cidr_allowlist = [
    "10.0.0.0/8", # PLACEHOLDER: corporate / VPN egress range — DO NOT ship as-is
  ]

  # SSO
  sso_instance_arn = "" # Populated after SSO setup
}
