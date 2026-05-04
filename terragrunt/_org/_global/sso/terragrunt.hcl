# ---------------------------------------------------------------------------------------------------------------------
# IAM Identity Center (SSO) — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Configures SSO permission sets, group lookups against the Identity Store,
# and account-level assignments wiring groups -> permission sets -> accounts.
# Depends on the Organization being created first.
#
# Group display names below MUST already exist in Identity Center (provisioned
# via SCIM from your IdP, or manually in the AWS console). The module looks
# them up by display name and resolves to real group IDs at plan time.
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

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
    account_ids = {
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
  organization_id = dependency.organization.outputs.organization_id
  member_accounts = local.account_vars.locals.member_accounts

  # ---------------------------------------------------------------------
  # Permission sets — see docs/runbooks/sso-permission-sets.md
  # ---------------------------------------------------------------------
  permission_sets = {
    AdministratorAccess = {
      description      = "Full admin access. Short session for break-glass / on-call only."
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      # Defensive guardrail — blocks the worst auto-renewing cost mistake.
      inline_policy_json = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid      = "DenyCreateSavingsPlan"
            Effect   = "Deny"
            Action   = "savingsplans:CreateSavingsPlan"
            Resource = "*"
          },
        ]
      })
    }

    ReadOnlyAccess = {
      description      = "Read-only access for auditing and inspection."
      session_duration = "PT8H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }

    PlatformEngineer = {
      description      = "Platform engineering — EKS, networking, infra observability."
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
        "arn:aws:iam::aws:policy/AmazonVPCFullAccess",
        "arn:aws:iam::aws:policy/CloudWatchFullAccess",
      ]
    }

    DeveloperAccess = {
      description      = "Developer access — non-prod accounts only. Power user minus IAM."
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/PowerUserAccess",
      ]
    }

    BillingAccess = {
      description      = "Billing read + cost reporting. Management account only."
      session_duration = "PT4H"
      managed_policies = [
        "arn:aws:iam::aws:policy/job-function/Billing",
      ]
    }

    SecurityAuditAccess = {
      description      = "Security audit (SecurityAudit + ViewOnlyAccess) across all accounts."
      session_duration = "PT8H"
      managed_policies = [
        "arn:aws:iam::aws:policy/SecurityAudit",
        "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess",
      ]
    }
  }

  # ---------------------------------------------------------------------
  # Identity Center groups — display names as they exist in the IdP.
  # The module resolves these to real group IDs via data sources.
  # ---------------------------------------------------------------------
  groups = {
    admins             = "PlatformAdmins"
    platform_engineers = "PlatformEngineers"
    developers         = "Developers"
    auditors           = "SecurityAuditors"
    billing            = "BillingTeam"
  }

  # ---------------------------------------------------------------------
  # Assignments: who gets what, where.
  # target_type = "ACCOUNT" resolves the short name against member_accounts.
  # AWS does not support OU targets — assignments must enumerate accounts.
  # ---------------------------------------------------------------------
  assignments = [
    # PlatformAdmins -> AdministratorAccess on every account
    { group_key = "admins", permission_set = "AdministratorAccess", target_type = "ACCOUNT", target_value = "network" },
    { group_key = "admins", permission_set = "AdministratorAccess", target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "admins", permission_set = "AdministratorAccess", target_type = "ACCOUNT", target_value = "staging" },
    { group_key = "admins", permission_set = "AdministratorAccess", target_type = "ACCOUNT", target_value = "prod" },
    { group_key = "admins", permission_set = "AdministratorAccess", target_type = "ACCOUNT", target_value = "dr" },

    # PlatformEngineers -> PlatformEngineer on infra/non-prod
    { group_key = "platform_engineers", permission_set = "PlatformEngineer", target_type = "ACCOUNT", target_value = "network" },
    { group_key = "platform_engineers", permission_set = "PlatformEngineer", target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "platform_engineers", permission_set = "PlatformEngineer", target_type = "ACCOUNT", target_value = "staging" },

    # PlatformEngineers -> ReadOnly on prod (no direct write)
    { group_key = "platform_engineers", permission_set = "ReadOnlyAccess", target_type = "ACCOUNT", target_value = "prod" },
    { group_key = "platform_engineers", permission_set = "ReadOnlyAccess", target_type = "ACCOUNT", target_value = "dr" },

    # Developers -> DeveloperAccess in non-prod ONLY
    { group_key = "developers", permission_set = "DeveloperAccess", target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "developers", permission_set = "DeveloperAccess", target_type = "ACCOUNT", target_value = "staging" },
    # Read-only into prod for incident debugging
    { group_key = "developers", permission_set = "ReadOnlyAccess", target_type = "ACCOUNT", target_value = "prod" },

    # SecurityAuditors -> SecurityAuditAccess everywhere (read-only audit)
    { group_key = "auditors", permission_set = "SecurityAuditAccess", target_type = "ACCOUNT", target_value = "network" },
    { group_key = "auditors", permission_set = "SecurityAuditAccess", target_type = "ACCOUNT", target_value = "dev" },
    { group_key = "auditors", permission_set = "SecurityAuditAccess", target_type = "ACCOUNT", target_value = "staging" },
    { group_key = "auditors", permission_set = "SecurityAuditAccess", target_type = "ACCOUNT", target_value = "prod" },
    { group_key = "auditors", permission_set = "SecurityAuditAccess", target_type = "ACCOUNT", target_value = "dr" },

    # BillingTeam -> BillingAccess on management only (consolidated billing lives here)
    { group_key = "billing", permission_set = "BillingAccess", target_type = "AWS_ACCOUNT_ID", target_value = local.account_vars.locals.account_id },
  ]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
  }
}
