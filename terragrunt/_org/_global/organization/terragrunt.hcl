# ---------------------------------------------------------------------------------------------------------------------
# AWS Organization — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Creates the AWS Organization with Organizational Units and member accounts.
# Must be applied from the management account.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/organization"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

inputs = {
  organization_name = local.account_vars.locals.organization_name
  member_accounts   = local.account_vars.locals.member_accounts

  organizational_units = {
    Security = {
      parent = "Root"
    }
    Infrastructure = {
      parent = "Root"
    }
    Workloads = {
      parent = "Root"
    }
    NonProd = {
      parent = "Workloads"
    }
    Prod = {
      parent = "Workloads"
    }
  }

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "sso.amazonaws.com",
    "ram.amazonaws.com",
    "securityhub.amazonaws.com",
  ]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
  }
}
