# ---------------------------------------------------------------------------------------------------------------------
# Tests — aws-ml-scp-parity (mocked AWS provider; plan-only, no apply, no real org policy)
# ---------------------------------------------------------------------------------------------------------------------
# Verifies the apply-gated / default-OFF contract and the ADR-0028 taxonomy + ABAC-style
# exemption wiring. ADR-0040 (GCP etalon) / ADR-0044 / ADR-0048.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "aws" {}

# --- 1. DEFAULT OFF: with no inputs, the module must create ZERO SCPs -------------------------------------------------
run "default_is_apply_gated_off" {
  command = plan

  assert {
    condition     = var.enabled == false
    error_message = "Module must default to apply-gated OFF (enabled=false)."
  }

  assert {
    condition     = length(aws_organizations_policy.require_imdsv2) == 0
    error_message = "Default (gated off) must create no IMDSv2 SCP."
  }

  assert {
    condition     = length(aws_organizations_policy.require_ebs_encryption) == 0
    error_message = "Default (gated off) must create no EBS-encryption SCP."
  }

  assert {
    condition     = length(aws_organizations_policy.deny_access_keys) == 0
    error_message = "Default (gated off) must create no access-key SCP."
  }

  assert {
    condition     = length(aws_organizations_policy.restrict_regions) == 0
    error_message = "Default (gated off) must create no region-restriction SCP."
  }

  assert {
    condition     = length(output.attached_ou_ids) == 0
    error_message = "No OU attachments may be reported when gated off."
  }
}

# --- 2. ENABLED but no target OU: policies materialise, attachments do not --------------------------------------------
run "enabled_no_target_ou_creates_policies_not_attachments" {
  command = plan

  variables {
    enabled          = true
    ml_target_ou_ids = []
  }

  assert {
    condition     = length(aws_organizations_policy.require_imdsv2) == 1
    error_message = "Enabling the gate must create the IMDSv2 SCP."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.require_imdsv2) == 0
    error_message = "With no target OU, no attachment may be created (blast-radius bound)."
  }
}

# --- 3. ENABLED with target OU: all four SCPs + taxonomy + naming ------------------------------------------------------
run "enabled_with_target_full_estate" {
  command = plan

  variables {
    enabled          = true
    project          = "platform-design"
    ml_target_ou_ids = ["ou-test-mlgpu01"]
  }

  assert {
    condition     = aws_organizations_policy.require_imdsv2[0].name == "platform-design-ml-RequireIMDSv2"
    error_message = "IMDSv2 SCP name must be prefixed project-ml-."
  }

  assert {
    condition     = aws_organizations_policy.require_imdsv2[0].tags["platform:system"] == "security"
    error_message = "ADR-0028 platform:system tag must be 'security' on every SCP."
  }

  assert {
    condition     = aws_organizations_policy.require_imdsv2[0].tags["platform:component"] == "scp-parity"
    error_message = "ADR-0028 platform:component tag must be 'scp-parity'."
  }

  assert {
    condition     = aws_organizations_policy.require_imdsv2[0].tags["platform:owner"] == "team-sec"
    error_message = "ADR-0028 platform:owner tag must be 'team-sec'."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.restrict_regions) == 1
    error_message = "Region-restriction SCP must attach to the single supplied ML OU."
  }

  assert {
    condition     = length(output.attached_ou_ids) == 1 && output.attached_ou_ids[0] == "ou-test-mlgpu01"
    error_message = "attached_ou_ids output must reflect the supplied ML OU."
  }
}

# --- 4. Per-policy toggle: disabling a single constraint drops only that SCP ------------------------------------------
run "per_policy_toggle_drops_only_that_scp" {
  command = plan

  variables {
    enabled                     = true
    ml_target_ou_ids            = ["ou-test-mlgpu01"]
    deny_long_lived_access_keys = false
  }

  assert {
    condition     = length(aws_organizations_policy.deny_access_keys) == 0
    error_message = "Disabling deny_long_lived_access_keys must drop that SCP only."
  }

  assert {
    condition     = length(aws_organizations_policy.require_imdsv2) == 1
    error_message = "Other SCPs must remain when one is toggled off."
  }
}
