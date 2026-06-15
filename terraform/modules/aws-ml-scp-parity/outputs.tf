# ---------------------------------------------------------------------------------------------------------------------
# Outputs — aws-ml-scp-parity
# ---------------------------------------------------------------------------------------------------------------------

output "policy_ids" {
  description = "Map of created ML SCP logical names to their AWS Organizations policy IDs. Empty when the module is gated off (var.enabled=false) — used by the catalog stack and the SOC2 evidence matrix for provenance."
  value = {
    require_imdsv2         = try(aws_organizations_policy.require_imdsv2[0].id, null)
    require_ebs_encryption = try(aws_organizations_policy.require_ebs_encryption[0].id, null)
    deny_access_keys       = try(aws_organizations_policy.deny_access_keys[0].id, null)
    restrict_regions       = try(aws_organizations_policy.restrict_regions[0].id, null)
  }
}

output "enabled" {
  description = "Echoes the master gate so a consuming stack / test can assert the module is apply-gated off by default."
  value       = var.enabled
}

output "platform_tags" {
  description = "The ADR-0028 taxonomy tags applied to every SCP in this module, surfaced for provenance so a reviewer / *.tftest.hcl can assert the taxonomy is present even though SCP resources are policy bindings."
  value       = var.tags
}

output "attached_ou_ids" {
  description = "The list of ML OU IDs the SCPs are attached to. Empty when gated off or no target supplied — confirms blast radius is bounded to the ML estate, never the org root."
  value       = var.enabled ? var.ml_target_ou_ids : []
}
