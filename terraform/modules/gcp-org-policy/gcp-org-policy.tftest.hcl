# ---------------------------------------------------------------------------------------------------------------------
# Tests for the gcp-org-policy module (WS-E — security / compliance).
# Uses a mocked google provider so no real GCP org / credentials are required — these
# are plan-time assertions over the module's logic. No org-policy is ever applied.
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "google" {}

variables {
  parent = "organizations/123456789012"

  labels = {
    platform_env   = "production"
    platform_owner = "team-sec"
  }
}

run "all_defaults_enforce_eight_constraints" {
  command = plan

  # Defaults: vmExternalIp, disableSAKeyCreation, disableSAKeyUpload, requireOsLogin,
  # sql.restrictPublicIp, uniformBucketLevelAccess, publicAccessPrevention, CMEK = 8.
  # gcp.resourceLocations is OFF by default (allowed_resource_locations is empty).
  assert {
    condition     = output.enforced_constraint_count == 8
    error_message = "With all defaults on and no locations set, the module should enforce eight constraints."
  }
}

run "vm_external_ip_denies_all_when_no_allowlist" {
  command = plan

  assert {
    condition     = google_org_policy_policy.vm_external_ip[0].spec[0].rules[0].deny_all == "TRUE"
    error_message = "With an empty allow-list, compute.vmExternalIpAccess must deny_all."
  }

  assert {
    condition     = google_org_policy_policy.vm_external_ip[0].name == "organizations/123456789012/policies/compute.vmExternalIpAccess"
    error_message = "Policy name must be parent/policies/<constraint>."
  }
}

run "sa_key_creation_enforced_true" {
  command = plan

  assert {
    condition     = google_org_policy_policy.disable_sa_key_creation[0].spec[0].rules[0].enforce == "TRUE"
    error_message = "iam.disableServiceAccountKeyCreation must be enforced TRUE."
  }
}

run "cmek_denies_listed_services" {
  command = plan

  assert {
    condition     = length(google_org_policy_policy.restrict_non_cmek_services) == 1
    error_message = "CMEK enforcement should be active when enforce_cmek is non-empty (default has four services)."
  }

  assert {
    condition     = contains(google_org_policy_policy.restrict_non_cmek_services[0].spec[0].rules[0].values[0].denied_values, "storage.googleapis.com")
    error_message = "CMEK constraint must deny non-CMEK storage by default."
  }
}

run "public_access_prevention_enforced_by_default" {
  command = plan

  assert {
    condition     = length(google_org_policy_policy.public_access_prevention) == 1
    error_message = "storage.publicAccessPrevention must be enforced by default (S3-PAB parity)."
  }
}

run "constraint_list_contains_expected_names" {
  command = plan

  assert {
    condition     = contains(output.enforced_constraints, "iam.disableServiceAccountKeyCreation")
    error_message = "enforced_constraints output must list the SA-key-creation constraint."
  }

  assert {
    condition     = contains(output.enforced_constraints, "gcp.restrictNonCmekServices")
    error_message = "enforced_constraints output must list the CMEK constraint."
  }
}

run "platform_labels_carry_security_system" {
  command = plan

  assert {
    condition     = output.platform_labels["platform_system"] == "security"
    error_message = "ADR-0028 platform_system must default to security for this module."
  }

  assert {
    condition     = output.platform_labels["platform_owner"] == "team-sec"
    error_message = "Caller label override (platform_owner = team-sec) must be merged in."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Toggle-off path — a staged rollout can carve a constraint out.
# -------------------------------------------------------------------------------------------------------------------

run "disabling_a_constraint_removes_it" {
  command = plan

  variables {
    disable_sa_key_upload            = false
    enforce_public_access_prevention = false
  }

  assert {
    condition     = length(google_org_policy_policy.disable_sa_key_upload) == 0
    error_message = "Setting disable_sa_key_upload = false must remove that policy."
  }

  assert {
    condition     = length(google_org_policy_policy.public_access_prevention) == 0
    error_message = "Setting enforce_public_access_prevention = false must remove that policy."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# allow-list path — external IP permitted for named instances instead of deny_all.
# -------------------------------------------------------------------------------------------------------------------

run "vm_external_ip_allowlist_permits_named" {
  command = plan

  variables {
    vm_external_ip_allowed_projects = ["projects/edge-ingress/zones/us-central1-a/instances/nat-gw-0"]
  }

  assert {
    condition     = google_org_policy_policy.vm_external_ip[0].spec[0].rules[0].deny_all == null
    error_message = "With an allow-list, deny_all must be null (allow-list takes over)."
  }

  assert {
    condition     = contains(google_org_policy_policy.vm_external_ip[0].spec[0].rules[0].values[0].allowed_values, "projects/edge-ingress/zones/us-central1-a/instances/nat-gw-0")
    error_message = "Allow-listed instance must appear in allowed_values."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# resource-location guardrail — only active when locations supplied.
# -------------------------------------------------------------------------------------------------------------------

run "resource_locations_active_when_supplied" {
  command = plan

  variables {
    allowed_resource_locations = ["in:us-locations", "in:eu-locations"]
  }

  assert {
    condition     = length(google_org_policy_policy.resource_locations) == 1
    error_message = "gcp.resourceLocations must be enforced when allowed_resource_locations is non-empty."
  }

  assert {
    condition     = contains(google_org_policy_policy.resource_locations[0].spec[0].rules[0].values[0].allowed_values, "in:eu-locations")
    error_message = "resourceLocations must carry the supplied allowed location groups."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# parent validation — reject a malformed parent.
# -------------------------------------------------------------------------------------------------------------------

run "rejects_malformed_parent" {
  command = plan

  variables {
    parent = "not-a-valid-parent"
  }

  expect_failures = [
    var.parent,
  ]
}
