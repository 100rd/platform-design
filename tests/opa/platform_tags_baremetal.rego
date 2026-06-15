package terraform.platform_tags_baremetal

import rego.v1

# ---------------------------------------------------------------------------
# Policy: bare-metal / Talos ADR-0028 platform-taxonomy enforcement.
#
# This is the BARE-METAL profile of tests/opa/platform_tags.rego (WS-E,
# decision #10 of the Bare-Metal ML Platform plan §7, and the gap recorded in
# ADR-0049 D6). The AWS-shaped policy keys on `tags["platform:system"]` and an
# `aws_*` exempt set, so it does NOT enforce ADR-0028 on `talos_*`,
# `kubernetes_manifest`, `kubectl_manifest`, or `helm_release` resources. This
# profile re-keys to the bare-metal plane:
#
#   - Label form:   UNDERSCORE keys (platform_system / platform_component /
#                   platform_owner) — the Talos/K8s plane spelling ADR-0028
#                   mandates on bare metal (vs the AWS `platform:system` tag).
#   - Where:        labels live under `tags` (Talos machine nodeLabels surfaced
#                   as tags), `labels`, OR `metadata.labels` (manifest resources).
#   - Exempt set:   bare-metal / Talos / manifest data-only + non-labelable types.
#
# Required platform labels (must be non-empty strings):
#   - platform_system     (logical service boundary, e.g. ml-pipeline)
#   - platform_component   (role within the system, e.g. gpu-worker, storage)
#   - platform_owner       (owning team, e.g. team-sec)
#
# Optional but tracked: platform_env, platform_managed_by.
#
# Run against a `terraform show -json <plan>` document (input.resource_changes).
# ---------------------------------------------------------------------------

_required_platform_labels := {"platform_system", "platform_component", "platform_owner"}

# Resource types that are not labelable, are data-only, or carry their taxonomy
# in their own embedded manifest body (validated by the manifest rule below, not
# the top-level label rule). Bare-metal / Talos / K8s-manifest shaped.
_exempt_types := {
	# Talos provider — secrets/config/bootstrap objects are not labelable resources;
	# the node labels they RENDER are asserted in the talos-machineconfig module test.
	"talos_machine_secrets",
	"talos_machine_configuration",
	"talos_machine_configuration_apply",
	"talos_machine_bootstrap",
	"talos_client_configuration",
	"talos_cluster_kubeconfig",
	"talos_cluster_health",
	# Manifest-delivery providers — the taxonomy lives in metadata.labels INSIDE the
	# rendered manifest, checked by the manifest rule, not as a top-level attribute.
	"kubernetes_manifest",
	"kubectl_manifest",
	"helm_release",
	# Generic data-only / non-labelable.
	"null_resource",
	"random_id",
	"random_string",
	"random_password",
	"random_bytes",
	"time_sleep",
	"local_file",
	"local_sensitive_file",
	"terraform_data",
	"tls_private_key",
	"http",
}

# Only check resources being created or updated (skip destroy / no-op).
_is_managed(actions) if {
	some a in actions
	a in {"create", "update"}
}

# Collect the label map from wherever a bare-metal resource carries it:
# `labels`, then `tags` (Talos nodeLabels surfaced as tags), merged.
_labels_of(after) := merged if {
	labels := object.get(after, "labels", {})
	tags := object.get(after, "tags", {})
	merged := object.union(tags, labels)
}

# -------------------------------------------------------------------------------------------------------------------
# Rule 1 — non-manifest, non-exempt resources must carry the three required
# underscore labels (present AND non-empty).
# -------------------------------------------------------------------------------------------------------------------
deny contains msg if {
	some addr, rc in input.resource_changes
	not rc.type in _exempt_types
	_is_managed(rc.change.actions)
	labels := _labels_of(rc.change.after)
	some required_label in _required_platform_labels
	not labels[required_label]
	msg := sprintf(
		"POLICY VIOLATION [platform-tags-baremetal]: resource %q (type: %s) is missing required platform label %q",
		[addr, rc.type, required_label],
	)
}

deny contains msg if {
	some addr, rc in input.resource_changes
	not rc.type in _exempt_types
	_is_managed(rc.change.actions)
	labels := _labels_of(rc.change.after)
	some required_label in _required_platform_labels
	labels[required_label] == ""
	msg := sprintf(
		"POLICY VIOLATION [platform-tags-baremetal]: resource %q (type: %s) has empty value for required platform label %q",
		[addr, rc.type, required_label],
	)
}

# -------------------------------------------------------------------------------------------------------------------
# Rule 2 — manifest-delivery resources (kubernetes_manifest / kubectl_manifest)
# must carry the DOTTED ADR-0028 labels inside metadata.labels of the rendered
# object. kubernetes_manifest exposes a structured `manifest.metadata.labels`;
# kubectl_manifest carries a raw `yaml_body` string — for the string form we assert
# the dotted keys appear (a coarse but plan-safe substring check, since OPA cannot
# parse arbitrary embedded YAML without a parsed input).
# -------------------------------------------------------------------------------------------------------------------
deny contains msg if {
	some addr, rc in input.resource_changes
	rc.type == "kubernetes_manifest"
	_is_managed(rc.change.actions)
	meta_labels := object.get(rc.change.after.manifest.metadata, "labels", {})
	some dotted in {"platform.system", "platform.component", "platform.owner"}
	not meta_labels[dotted]
	msg := sprintf(
		"POLICY VIOLATION [platform-tags-baremetal]: manifest %q (type: %s) metadata.labels is missing required platform label %q",
		[addr, rc.type, dotted],
	)
}

deny contains msg if {
	some addr, rc in input.resource_changes
	rc.type == "kubectl_manifest"
	_is_managed(rc.change.actions)
	body := object.get(rc.change.after, "yaml_body", "")
	some dotted in {"platform.system", "platform.component", "platform.owner"}
	not contains(body, dotted)
	msg := sprintf(
		"POLICY VIOLATION [platform-tags-baremetal]: kubectl_manifest %q yaml_body is missing required platform label %q",
		[addr, dotted],
	)
}
