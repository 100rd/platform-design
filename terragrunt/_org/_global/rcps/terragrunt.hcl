# ---------------------------------------------------------------------------------------------------------------------
# Resource Control Policies (RCPs) — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Provenance: ADR-0017 (resource-side data perimeter). Defines the org-perimeter
# RCP — the resource-side half of the data perimeter, complementing the
# principal-side SCP in ../scps.
#
# STAGED ROLLOUT → ROOT PROMOTION (ADR-0017 Implementation notes steps 3–4):
#   step 3 (done)    — attached to the Policy-Staging OU FIRST (a small
#                      test-account set) so a mis-scoped deny is caught in a
#                      limited blast radius.
#   step 4 (THIS)    — post-soak, promote to root by appending the organization
#                      root id to target_ou_ids. The attachment is for_each, so
#                      adding the root id is ADDITIVE: the Policy-Staging
#                      attachment is retained alongside the new root attachment,
#                      and removal of the root id cleanly reverts to staged-only.
#
# ROLLBACK: remove `dependency.organization.outputs.root_id` from target_ou_ids
#   below and re-plan/apply. Because the org-perimeter policy resource itself is
#   unchanged, this detaches the RCP from root while leaving it attached to
#   Policy-Staging — a single-line, blast-radius-bounded revert. To disable the
#   control entirely, empty target_ou_ids (the policy stays defined but unattached).
#
# Depends on the Organization (for the org id, the Policy-Staging OU id, and the
# root id) and on RESOURCE_CONTROL_POLICY being enabled in ../organization's
# enabled_policy_types.
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
    root_id              = "r-mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  organization_id = dependency.organization.outputs.organization_id

  # PROMOTED TO ROOT (ADR-0017 step 4, post-soak). The org-perimeter RCP is now
  # attached to BOTH the Policy-Staging OU and the organization root. The
  # attachment is for_each over this set, so the root promotion was additive and
  # is reversible: drop the root_id line to detach from root and fall back to
  # staged-only (see ROLLBACK in the header).
  target_ou_ids = [
    dependency.organization.outputs.policy_staging_ou_id,
    dependency.organization.outputs.root_id,
  ]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    ADR         = "0017"
  }
}
