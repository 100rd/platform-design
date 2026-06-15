# ---------------------------------------------------------------------------------------------------------------------
# Tests for the baremetal-org-policy module (WS-E — security / compliance).
# Mocked talos + kubectl providers — no real Talos cluster / credentials required.
# These are plan-time assertions over the module's posture-evaluation and
# policy-bundle-rendering logic. No policy CR is ever applied (deploy_policy_bundle
# defaults false, so the kubectl_manifest for_each is empty).
# ---------------------------------------------------------------------------------------------------------------------

mock_provider "talos" {}
mock_provider "kubectl" {}

variables {
  cluster_name = "talos-uk-primary"
  dc_name      = "uk-primary"

  labels = {
    platform_env   = "production"
    platform_owner = "team-sec"
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Default posture: all five assertions ON, observed posture compliant => no violations.
# -------------------------------------------------------------------------------------------------------------------
run "compliant_posture_has_no_violations" {
  command = plan

  assert {
    condition     = output.posture_compliant == true
    error_message = "With a compliant observed posture and all assertions on, posture_compliant must be true."
  }

  assert {
    condition     = length(output.posture_violations) == 0
    error_message = "A compliant posture must yield zero posture_violations."
  }

  assert {
    condition     = length(output.active_assertions) == 5
    error_message = "All five Talos posture assertions (no-ssh, mtls, kubeprism, immutable, no-pkg-mgr) must be active by default."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# A drifted node (SSH enabled) must surface a no_ssh violation mapped to its SOC2 family.
# -------------------------------------------------------------------------------------------------------------------
run "ssh_enabled_drift_is_flagged" {
  command = plan

  variables {
    observed_ssh_enabled = true
  }

  assert {
    condition     = output.posture_compliant == false
    error_message = "An SSH-enabled node must make the posture non-compliant."
  }

  assert {
    condition     = length(output.posture_violations) == 1
    error_message = "Exactly one violation (no_ssh) must be reported when SSH is the only drift."
  }

  assert {
    condition     = output.posture_violations[0].assertion == "no_ssh"
    error_message = "The flagged violation must be the no_ssh assertion."
  }

  assert {
    condition     = output.posture_violations[0].soc2 == "CC6.1/CC6.6"
    error_message = "The no_ssh violation must carry its SOC2 control family CC6.1/CC6.6."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# KubePrism disabled + plaintext machine API => two violations.
# -------------------------------------------------------------------------------------------------------------------
run "multiple_drift_reports_each_violation" {
  command = plan

  variables {
    observed_kubeprism_enabled = false
    observed_machine_api_mtls  = false
  }

  assert {
    condition     = length(output.posture_violations) == 2
    error_message = "Two simultaneous drifts (kubeprism off, mtls off) must produce two violations."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Turning an assertion OFF (staged carve-out) removes it from active_assertions and
# means its drift is NOT flagged.
# -------------------------------------------------------------------------------------------------------------------
run "disabling_assertion_silences_its_drift" {
  command = plan

  variables {
    assert_no_ssh        = false
    observed_ssh_enabled = true
  }

  assert {
    condition     = length(output.active_assertions) == 4
    error_message = "Disabling assert_no_ssh must drop active assertions to four."
  }

  assert {
    condition     = output.posture_compliant == true
    error_message = "With the no_ssh assertion disabled, an SSH drift must not break compliance."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Posture -> SOC2 map is populated for every active assertion.
# -------------------------------------------------------------------------------------------------------------------
run "soc2_map_covers_every_assertion" {
  command = plan

  assert {
    condition     = output.posture_soc2_map["kubeprism"] == "A1.2/CC7.5"
    error_message = "kubeprism must map to SOC2 A1.2/CC7.5."
  }

  assert {
    condition     = output.posture_soc2_map["no_package_manager"] == "CC6.8"
    error_message = "no_package_manager must map to SOC2 CC6.8 (unauthorized software)."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Policy bundle: built-ins rendered, named per cluster, DEFAULT-OFF (not deployed).
# -------------------------------------------------------------------------------------------------------------------
run "default_renders_two_builtin_policies_not_deployed" {
  command = plan

  assert {
    condition     = length(output.policy_bundle_names) == 2
    error_message = "By default both built-in tenant policies (require-tenant-label, deny-cross-ns-sa) must render."
  }

  assert {
    condition     = contains(output.policy_bundle_names, "require-tenant-label")
    error_message = "The require-tenant-label built-in must be in the bundle."
  }

  assert {
    condition     = output.policy_bundle_deployed == false
    error_message = "deploy_policy_bundle defaults false — the bundle must NOT be delivered in plan-only mode."
  }

  assert {
    condition     = length(kubectl_manifest.policy) == 0
    error_message = "With deploy_policy_bundle = false, zero kubectl_manifest resources must be planned (apply-gated)."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Rendered CR carries the cluster-scoped name + the dotted ADR-0028 labels.
# -------------------------------------------------------------------------------------------------------------------
run "rendered_policy_carries_taxonomy_and_name" {
  command = plan

  assert {
    condition     = strcontains(output.policy_bundle_yaml["require-tenant-label"], "bm-talos-uk-primary-require-tenant-label")
    error_message = "The tenant-label policy must be named bm-<cluster>-require-tenant-label."
  }

  assert {
    condition     = strcontains(output.policy_bundle_yaml["require-tenant-label"], "\"platform.system\": \"security\"")
    error_message = "The rendered CR must carry the dotted ADR-0028 platform.system label."
  }

  assert {
    condition     = strcontains(output.policy_bundle_yaml["require-tenant-label"], "\"platform.owner\": \"team-sec\"")
    error_message = "Caller label override (platform_owner = team-sec) must be re-keyed to dotted form in the CR."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Disabling a built-in policy removes it from the bundle.
# -------------------------------------------------------------------------------------------------------------------
run "disabling_builtin_removes_it" {
  command = plan

  variables {
    enforce_no_cross_ns_sa = false
  }

  assert {
    condition     = length(output.policy_bundle_names) == 1
    error_message = "Disabling enforce_no_cross_ns_sa must leave only the tenant-label policy."
  }

  assert {
    condition     = !contains(output.policy_bundle_names, "deny-cross-ns-sa")
    error_message = "deny-cross-ns-sa must be absent when its toggle is false."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Enforcement mode flows into the rendered CR.
# -------------------------------------------------------------------------------------------------------------------
run "enforce_mode_threads_into_cr" {
  command = plan

  variables {
    policy_enforcement_mode = "Enforce"
  }

  assert {
    condition     = strcontains(output.policy_bundle_yaml["require-tenant-label"], "\"validationFailureAction\": \"Enforce\"")
    error_message = "policy_enforcement_mode = Enforce must set validationFailureAction: Enforce in the CR."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# platform_labels default to the security system with the caller override merged.
# -------------------------------------------------------------------------------------------------------------------
run "platform_labels_default_security_system" {
  command = plan

  assert {
    condition     = output.platform_labels["platform_system"] == "security"
    error_message = "platform_system must default to security for this module."
  }

  assert {
    condition     = output.platform_labels["platform_owner"] == "team-sec"
    error_message = "Caller label override (platform_owner = team-sec) must be merged in."
  }
}

# -------------------------------------------------------------------------------------------------------------------
# Validation: reject a non-UK dc_name and a malformed cluster_name.
# -------------------------------------------------------------------------------------------------------------------
run "rejects_invalid_dc_name" {
  command = plan

  variables {
    dc_name = "us-east-1"
  }

  expect_failures = [
    var.dc_name,
  ]
}

run "rejects_malformed_cluster_name" {
  command = plan

  variables {
    cluster_name = "Talos_UK_Primary"
  }

  expect_failures = [
    var.cluster_name,
  ]
}
