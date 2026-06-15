package terraform.platform_tags_baremetal

import rego.v1

# ---------------------------------------------------------------------------
# Unit tests for the bare-metal ADR-0028 tag-enforcement profile.
# Run: opa test tests/opa/
#
# Each test feeds a synthetic `terraform show -json`-shaped plan fragment as
# `input` and asserts the deny set. These prove the WS-E acceptance criterion:
# "the platform_tags_baremetal.rego OPA profile flags a talos_* /
# kubernetes_manifest resource missing the ADR-0028 keys at plan time".
# ---------------------------------------------------------------------------

# A bare-metal compute resource WITH all three underscore labels => no deny.
test_compliant_resource_passes if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "kubernetes_namespace.tenant",
		"type": "kubernetes_namespace",
		"change": {
			"actions": ["create"],
			"after": {"labels": {
				"platform_system": "ml-pipeline",
				"platform_component": "namespace",
				"platform_owner": "team-ml-platform",
			}},
		},
	}]}
}

# Same resource MISSING platform_owner => exactly one deny naming that key.
test_missing_owner_is_flagged if {
	result := deny with input as {"resource_changes": [{
		"address": "kubernetes_namespace.tenant",
		"type": "kubernetes_namespace",
		"change": {
			"actions": ["create"],
			"after": {"labels": {
				"platform_system": "ml-pipeline",
				"platform_component": "namespace",
			}},
		},
	}]}
	count(result) == 1
	some m in result
	contains(m, "platform_owner")
}

# A resource carrying labels under `tags` (Talos nodeLabels surfaced as tags) passes.
test_tags_form_satisfies_requirement if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "some_node.gpu0",
		"type": "some_labelable_node",
		"change": {
			"actions": ["create"],
			"after": {"tags": {
				"platform_system": "gpu-foundation",
				"platform_component": "gpu-worker",
				"platform_owner": "team-sec",
			}},
		},
	}]}
}

# An empty value for a required label is rejected (not just absence).
test_empty_value_is_flagged if {
	result := deny with input as {"resource_changes": [{
		"address": "kubernetes_namespace.tenant",
		"type": "kubernetes_namespace",
		"change": {
			"actions": ["create"],
			"after": {"labels": {
				"platform_system": "",
				"platform_component": "namespace",
				"platform_owner": "team-sec",
			}},
		},
	}]}
	count(result) == 1
	some m in result
	contains(m, "empty value")
}

# Talos secrets/config objects are EXEMPT (not labelable) => no deny even unlabeled.
test_talos_machine_config_is_exempt if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "talos_machine_configuration.cp",
		"type": "talos_machine_configuration",
		"change": {"actions": ["create"], "after": {}},
	}]}
}

# Destroy / no-op actions are NOT evaluated.
test_destroy_action_is_skipped if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "kubernetes_namespace.old",
		"type": "kubernetes_namespace",
		"change": {"actions": ["delete"], "after": null},
	}]}
}

# A kubectl_manifest whose yaml_body carries the DOTTED labels passes.
test_kubectl_manifest_with_dotted_labels_passes if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "kubectl_manifest.policy[\"require-tenant-label\"]",
		"type": "kubectl_manifest",
		"change": {
			"actions": ["create"],
			"after": {"yaml_body": "metadata:\n  labels:\n    platform.system: security\n    platform.component: org-policy\n    platform.owner: team-sec\n"},
		},
	}]}
}

# A kubectl_manifest MISSING the dotted labels is flagged (the WS-E acceptance:
# the AWS-shaped rego would NOT catch this; the bare-metal profile does).
test_kubectl_manifest_missing_labels_is_flagged if {
	result := deny with input as {"resource_changes": [{
		"address": "kubectl_manifest.policy[\"x\"]",
		"type": "kubectl_manifest",
		"change": {
			"actions": ["create"],
			"after": {"yaml_body": "metadata:\n  labels:\n    app: foo\n"},
		},
	}]}
	count(result) == 3
}

# A kubernetes_manifest with structured metadata.labels carrying the dotted keys passes.
test_kubernetes_manifest_with_labels_passes if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "kubernetes_manifest.cr",
		"type": "kubernetes_manifest",
		"change": {
			"actions": ["create"],
			"after": {"manifest": {"metadata": {"labels": {
				"platform.system": "observability",
				"platform.component": "dashboard",
				"platform.owner": "team-sre",
			}}}},
		},
	}]}
}

# A kubernetes_manifest missing the dotted keys in metadata.labels is flagged.
test_kubernetes_manifest_missing_labels_is_flagged if {
	result := deny with input as {"resource_changes": [{
		"address": "kubernetes_manifest.cr",
		"type": "kubernetes_manifest",
		"change": {
			"actions": ["create"],
			"after": {"manifest": {"metadata": {"labels": {"app": "foo"}}}},
		},
	}]}
	count(result) == 3
}
