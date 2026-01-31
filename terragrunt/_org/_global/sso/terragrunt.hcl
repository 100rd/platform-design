# ---------------------------------------------------------------------------------------------------------------------
# IAM Identity Center (SSO) — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Configures SSO permission sets and account assignments for human access.
# Depends on the Organization being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/sso"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organization_id = "o-mock"
    account_ids     = {
      network = "555555555555"
      dev     = "111111111111"
      staging = "222222222222"
      prod    = "333333333333"
      dr      = "666666666666"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  organization_id  = dependency.organization.outputs.organization_id
  member_accounts  = local.account_vars.locals.member_accounts

  permission_sets = {
    AdministratorAccess = {
      description      = "Full admin access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    ReadOnlyAccess = {
      description      = "Read-only access for auditing"
      session_duration = "PT8H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    PlatformEngineer = {
      description      = "Platform engineering access (EKS, Terraform, networking)"
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
        "arn:aws:iam::aws:policy/AmazonVPCFullAccess",
      ]
    }
    DeveloperAccess = {
      description      = "Developer access (limited to non-prod)"
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
      ]
    }
  }

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
  }
}
