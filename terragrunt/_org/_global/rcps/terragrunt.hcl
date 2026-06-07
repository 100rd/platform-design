# ---------------------------------------------------------------------------------------------------------------------
# Resource Control Policies (RCPs) — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Provenance: ADR-0017 (resource-side data perimeter). Defines the org-perimeter
# RCP — the resource-side half of the data perimeter, complementing the
# principal-side SCP in ../scps.
#
# STAGED ROLLOUT (ADR-0017 Implementation notes step 3):
#   The RCP is attached to the Policy-Staging OU FIRST (a small test-account set)
#   so a mis-scoped deny is caught in a limited blast radius. Promote to root by
#   appending the root id to target_ou_ids once staging is verified clean.
#
# Depends on the Organization (for the org id, the Policy-Staging OU id) and on
# RESOURCE_CONTROL_POLICY being enabled in ../organization's enabled_policy_types.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/rcps"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
}

dependency "organization" {
  config_path = "../organization"

  mock_outputs = {
    organization_id      = "o-mock"
    policy_staging_ou_id = "ou-mock-policy-staging"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  organization_id = dependency.organization.outputs.organization_id

  # STAGED: attach ONLY to the Policy-Staging OU first (ADR-0017 step 3).
  # To PROMOTE to root (step 4), append the organization root id here once
  # staging is verified clean — the attachment is for_each, so this is additive.
  target_ou_ids = [
    dependency.organization.outputs.policy_staging_ou_id,
  ]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    ADR         = "0017"
  }
}
