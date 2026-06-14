mock_provider "google" {}

variables {
  project_id           = "test-gcp-project"
  security_policy_name = "gpu-inference-armor-test"
  labels = {
    "platform.system" = "ml-infra"
  }
}

run "policy_is_cloud_armor_type" {
  command = plan

  assert {
    condition     = google_compute_security_policy.this[0].type == "CLOUD_ARMOR"
    error_message = "Security policy must be of type CLOUD_ARMOR."
  }
}

run "adaptive_protection_on_by_default" {
  command = plan

  assert {
    condition     = google_compute_security_policy.this[0].adaptive_protection_config[0].layer_7_ddos_defense_config[0].enable == true
    error_message = "Adaptive Protection (L7 DDoS defense) must default to enabled."
  }
}

run "waf_rules_create_rule_per_expression" {
  # apply (against the mock provider) so the computed rule set is known.
  command = apply

  variables {
    waf_preconfigured_rules = ["sqli-v33-stable", "xss-v33-stable", "lfi-v33-stable"]
  }

  # rate-limit (1) + WAF (3) + default-allow (1) = 5 rules.
  assert {
    condition     = length(google_compute_security_policy.this[0].rule) == 5
    error_message = "Expected 5 rules: 1 rate-limit + 3 WAF + 1 default-allow."
  }
}

run "disabled_creates_nothing" {
  command = plan

  variables {
    enabled = false
  }

  assert {
    condition     = length(google_compute_security_policy.this) == 0
    error_message = "No security policy should be created when enabled = false."
  }
}
