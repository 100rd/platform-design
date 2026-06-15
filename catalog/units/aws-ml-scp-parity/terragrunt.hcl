# ---------------------------------------------------------------------------------------------------------------------
# aws-ml-scp-parity — Catalog Unit (WS-E)
# ---------------------------------------------------------------------------------------------------------------------
# ML-OU-scoped SCP deny-list plane for the greenfield AWS GPU/ML estate (ADR-0044/0048,
# AWS analog of the GCP org-policy plane in ADR-0040 D1). Deploy in the MANAGEMENT
# account (SCPs are an Organizations-level resource).
#
# APPLY-GATED: `enabled = false` by default — plan/validate is inert and creates no SCP.
# Set `enabled = true` and populate `ml_target_ou_ids` only behind an explicit human
# apply + blast-radius review (SCPs are org-wide).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/aws-ml-scp-parity"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

inputs = {
  project = "platform-design"

  # apply-gated OFF until a human enables it with a reviewed plan.
  enabled = false

  # TODO: populate with the GPU/ML OU id(s) when enabling (e.g. ["ou-xxxx-mlgpu01"]).
  ml_target_ou_ids = []

  allowed_gpu_regions = ["eu-west-1", "us-east-1", "us-west-2"]

  # Per-policy toggles (all on; the master `enabled` gate still defaults the unit OFF).
  require_imdsv2              = true
  require_ebs_encryption      = true
  deny_long_lived_access_keys = true
  restrict_gpu_regions        = true

  tags = {
    "platform:system"     = "security"
    "platform:component"  = "scp-parity"
    "platform:owner"      = "team-sec"
    "platform:env"        = local.environment
    "platform:managed-by" = "terragrunt"
  }
}
