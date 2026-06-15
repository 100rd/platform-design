# ---------------------------------------------------------------------------------------------------------------------
# Outputs for the baremetal-org-policy module (WS-E — security / compliance).
# ---------------------------------------------------------------------------------------------------------------------

output "cluster_name" {
  description = "The Talos cluster this posture/policy bundle binds to."
  value       = var.cluster_name
}

output "active_assertions" {
  description = "Talos OS posture assertions currently turned ON (the immutable-OS controls evaluated at plan time)."
  value       = keys(local.active_assertions)
}

output "posture_violations" {
  description = "Posture assertions that are ON but whose OBSERVED Talos posture does not satisfy them. Empty list = compliant. Each entry: { assertion, soc2, detail }."
  value       = local.posture_violations
}

output "posture_compliant" {
  description = "True when every active Talos posture assertion is satisfied by the observed machine config (no SSH, mTLS API, KubePrism, immutable install, no package manager). The boolean the SOC2 matrix / CI gate reads."
  value       = local.posture_compliant
}

output "posture_soc2_map" {
  description = "Map of each active posture assertion to its SOC2 control family — the control-to-evidence link the matrix cites."
  value = {
    for k, v in local.active_assertions : k => v.soc2
  }
}

output "policy_bundle_names" {
  description = "Names of the Kyverno/Gatekeeper policy CRs in the bundle (built-ins + caller extras). Rendered even when deploy_policy_bundle is false, so a reviewer can see what WOULD be delivered."
  value       = keys(local.policy_bundle)
}

output "policy_bundle_yaml" {
  description = "The rendered policy CR YAML documents keyed by id (for plan-time review). Materialised as kubectl_manifest only when deploy_policy_bundle = true."
  value       = local.policy_bundle
}

output "policy_bundle_deployed" {
  description = "Whether the policy bundle is actually being delivered as kubectl_manifest resources (apply-gated). False in default/plan-only mode."
  value       = var.deploy_policy_bundle
}

output "platform_labels" {
  description = "ADR-0028 taxonomy for this module instance (underscore form; provenance — posture assertions and CR bindings are not labelable Terraform resources)."
  value       = local.platform_labels
}
