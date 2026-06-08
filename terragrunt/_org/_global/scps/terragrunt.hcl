# ---------------------------------------------------------------------------------------------------------------------
# Service Control Policies — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Defines guardrail SCPs attached to OUs. Enforces security boundaries across the organization.
# Depends on the Organization being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/scps"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organization_id = "o-mock"
    ou_ids = {
      Root           = "r-mock"
      Security       = "ou-mock-sec"
      Infrastructure = "ou-mock-infra"
      Workloads      = "ou-mock-work"
      NonProd        = "ou-mock-nonprod"
      Prod           = "ou-mock-prod"
      Deployments    = "ou-mock-deploy"
      Sandbox        = "ou-mock-sandbox"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  organization_id = dependency.organization.outputs.organization_id
  ou_ids          = dependency.organization.outputs.ou_ids

  # OUs treated as workload-bearing — deny-root-account SCP attaches to these.
  # Includes Sandbox (#158) so developer-experiment accounts can't use root.
  # Deployments NOT included — its accounts run AFT/CI tooling under
  # programmatic IAM principals; SCPs are inherited from non-workload defaults.
  workload_ou_names = ["NonProd", "Prod", "Sandbox"]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
  }
}
