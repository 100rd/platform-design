# ---------------------------------------------------------------------------------------------------------------------
# GuardDuty Organization — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Enables GuardDuty across the organization and delegates administration.
# Depends on the Organization being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/guardduty-org"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organization_id = "o-mock"
    account_ids     = {}
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  # Delegate GuardDuty admin to the management account itself
  # or to a dedicated security account if created later
  delegated_admin_account_id = local.account_vars.locals.account_id

  enable_s3_protection        = true
  enable_eks_protection       = true
  enable_malware_protection   = true
  auto_enable_new_accounts    = true

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
  }
}
