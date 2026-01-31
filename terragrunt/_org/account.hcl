locals {
  account_name = "management"
  account_id   = "000000000000" # TODO: Replace with actual AWS management account ID
  aws_account_id = "000000000000"
  environment  = "management"

  # Organization context
  org_account_type = "management"
  org_ou           = "Root"

  # Organization structure
  organization_name = "platform-org"
  organization_id   = "" # Populated after org creation

  # Member accounts
  member_accounts = {
    network = {
      account_id = "555555555555"
      email      = "aws+network@example.com"
      ou         = "Infrastructure"
    }
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
    prod = {
      account_id = "333333333333"
      email      = "aws+prod@example.com"
      ou         = "Prod"
    }
    dr = {
      account_id = "666666666666"
      email      = "aws+dr@example.com"
      ou         = "Prod"
    }
  }

  # Network account reference
  network_account_id = "555555555555"

  # SSO
  sso_instance_arn = "" # Populated after SSO setup
}
