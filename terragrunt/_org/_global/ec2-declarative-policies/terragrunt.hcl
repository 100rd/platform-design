# ---------------------------------------------------------------------------------------------------------------------
# EC2 Declarative Policies — Management Account
# ---------------------------------------------------------------------------------------------------------------------
# Provenance: ADR-0017 (declarative org controls), Decision item 2. Companion to ../rcps
# and ../scps. Enforces the EC2 control-plane baseline org-wide: IMDSv2 required, block
# public EBS-snapshot/AMI sharing, allowed-AMI providers.
#
# STAGED ROLLOUT (ADR-0017 Implementation notes step 3 — THIS):
#   Attached to the Policy-Staging OU ONLY, with allowed_images_state = audit_mode
#   (log-only), so a mis-scoped setting is caught in a limited blast radius before any
#   instance launch is blocked.
#
# ROOT PROMOTION (step 4, later, post-soak):
#   Append `dependency.organization.outputs.root_id` to target_ou_ids (additive for_each)
#   and flip allowed_images_state -> "enabled". Then retire the require_imdsv2 SCP.
#
# ROLLBACK: drop the root id (revert to staged-only) or empty target_ou_ids (policy stays
#   defined-but-unattached). See module README.
#
# Depends on the Organization (Policy-Staging OU id + root id) and on
# DECLARATIVE_POLICY_EC2 being enabled in ../organization's enabled_policy_types.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/ec2-declarative-policies"
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
  # STAGED (ADR-0017 step 3): Policy-Staging OU only. Promote to root by appending
  # dependency.organization.outputs.root_id post-soak (additive/reversible).
  target_ou_ids = [
    dependency.organization.outputs.policy_staging_ou_id,
  ]

  # Baseline controls (ADR-0017 item 2).
  require_imdsv2             = true
  block_public_ebs_snapshots = true
  block_public_amis          = true

  # Allowed-AMI providers stay in audit_mode during staging; flip to "enabled" at root promotion.
  enable_allowed_images   = true
  allowed_images_state    = "audit_mode"
  allowed_image_providers = ["amazon"]

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    ADR         = "0017"
  }
}
