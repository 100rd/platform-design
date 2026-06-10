# ---------------------------------------------------------------------------------------------------------------------
# Outputs for the gcp-org-policy module (WS-E — security / compliance).
# ---------------------------------------------------------------------------------------------------------------------

output "parent" {
  description = "The resource-manager node the policies are bound to."
  value       = var.parent
}

output "enforced_constraints" {
  description = "GCP org-policy constraint names actually enforced by this module instance (count-gated resources only appear when enabled)."
  value = compact([
    length(google_org_policy_policy.vm_external_ip) > 0 ? "compute.vmExternalIpAccess" : "",
    length(google_org_policy_policy.disable_sa_key_creation) > 0 ? "iam.disableServiceAccountKeyCreation" : "",
    length(google_org_policy_policy.disable_sa_key_upload) > 0 ? "iam.disableServiceAccountKeyUpload" : "",
    length(google_org_policy_policy.require_os_login) > 0 ? "compute.requireOsLogin" : "",
    length(google_org_policy_policy.restrict_public_ip_cloudsql) > 0 ? "sql.restrictPublicIp" : "",
    length(google_org_policy_policy.uniform_bucket_level_access) > 0 ? "storage.uniformBucketLevelAccess" : "",
    length(google_org_policy_policy.public_access_prevention) > 0 ? "storage.publicAccessPrevention" : "",
    length(google_org_policy_policy.restrict_non_cmek_services) > 0 ? "gcp.restrictNonCmekServices" : "",
    length(google_org_policy_policy.resource_locations) > 0 ? "gcp.resourceLocations" : "",
  ])
}

output "enforced_constraint_count" {
  description = "Number of org-policy constraints enforced by this module instance."
  value = (
    length(google_org_policy_policy.vm_external_ip) +
    length(google_org_policy_policy.disable_sa_key_creation) +
    length(google_org_policy_policy.disable_sa_key_upload) +
    length(google_org_policy_policy.require_os_login) +
    length(google_org_policy_policy.restrict_public_ip_cloudsql) +
    length(google_org_policy_policy.uniform_bucket_level_access) +
    length(google_org_policy_policy.public_access_prevention) +
    length(google_org_policy_policy.restrict_non_cmek_services) +
    length(google_org_policy_policy.resource_locations)
  )
}

output "platform_labels" {
  description = "ADR-0028 taxonomy recorded for this module instance (provenance; org-policy resources are not labelable)."
  value       = local.platform_labels
}
