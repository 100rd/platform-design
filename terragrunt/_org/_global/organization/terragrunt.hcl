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

  # OU hierarchy. Issue #158 calls for the canonical 5-OU split:
  #   Production / Non-Production / Deployments / Suspended / Sandbox.
  # We keep our existing OU names (Security, Infrastructure, Workloads,
  # NonProd, Prod) for backwards compatibility with already-deployed SCPs
  # and SSO permission-set assignments — see docs/ou-structure.md for the
  # mapping. New OUs (Deployments, Sandbox) are added top-level. Suspended
  # is created as a hard-coded top-level OU inside the organization module.
  #
  # Aliases (this repo -> canonical name):
  #   Prod        -> Production
  #   NonProd     -> Non-Production
  #   Deployments -> Deployments     (new)
  #   Sandbox     -> Sandbox         (new)
  #   Suspended   -> Suspended       (already created by module)
  organizational_units = {
    # --- Security tier ---
    Security = {
      parent = "Root"
    }
    # --- Infrastructure tier ---
    Infrastructure = {
      parent = "Root"
    }
    # --- Workloads tier ---
    Workloads = {
      parent = "Root"
    }
    NonProd = {
      parent = "Workloads"
    }
    Prod = {
      parent = "Workloads"
    }
    # --- Deployments tier (NEW per #158) ---
    # Holds the AFT (Account Factory for Terraform) account, CI/CD
    # automation accounts, and deployment-specific service accounts.
    # SCPs allow CodeBuild/CodePipeline IAM but block workload data plane.
    Deployments = {
      parent = "Root"
    }
    # --- Sandbox tier (NEW per #158) ---
    # Developer experimentation accounts, isolated from prod data and
    # main IAM trust paths. Region-restricted via SCP, no shared services
    # access. Spend caps enforced via Budgets module (#175).
    Sandbox = {
      parent = "Root"
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
