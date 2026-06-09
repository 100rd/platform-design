package terraform.platform_tags

import rego.v1

# ---------------------------------------------------------------------------
# Policy: All managed resources must carry the platform taxonomy tags
#
# Required platform tags (must be non-empty strings):
#   - platform:system     (logical service boundary, e.g. auth-service)
#   - platform:component  (role within the system, e.g. backend, cache, db)
#   - platform:owner      (owning team or individual)
#
# Optional but tracked:
#   - platform:env        (deployment environment)
#   - platform:managed-by (provisioning tool)
#
# Resources that do not support tags (data sources, IAM policy documents,
# null_resource, etc.) are excluded via _exempt_types.
# ---------------------------------------------------------------------------

_required_platform_tags := {"platform:system", "platform:component", "platform:owner"}

# Resource types that are not taggable or are data-only
_exempt_types := {
  "aws_iam_policy_document",
  "aws_iam_role_policy",
  "aws_caller_identity",
  "aws_region",
  "aws_availability_zones",
  "aws_partition",
  "null_resource",
  "random_id",
  "random_string",
  "random_password",
  "time_sleep",
  "local_file",
  "terraform_data",
  "aws_sqs_queue_redrive_allow_policy",
  "aws_vpclattice_auth_policy",
}

# Only check resources being created or updated (skip destroy/no-op)
_is_managed(actions) if {
  some a in actions
  a in {"create", "update"}
}

deny contains msg if {
  some addr, rc in input.resource_changes
  not rc.type in _exempt_types
  _is_managed(rc.change.actions)
  tags := object.get(rc.change.after, "tags", {})
  some required_tag in _required_platform_tags
  not tags[required_tag]
  msg := sprintf(
    "POLICY VIOLATION [platform-tags]: resource %q (type: %s) is missing required platform tag %q",
    [addr, rc.type, required_tag],
  )
}

# Also flag tags that are present but empty
deny contains msg if {
  some addr, rc in input.resource_changes
  not rc.type in _exempt_types
  _is_managed(rc.change.actions)
  tags := object.get(rc.change.after, "tags", {})
  some required_tag in _required_platform_tags
  tags[required_tag] == ""
  msg := sprintf(
    "POLICY VIOLATION [platform-tags]: resource %q (type: %s) has empty value for required platform tag %q",
    [addr, rc.type, required_tag],
  )
}
