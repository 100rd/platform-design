package terraform.required_tags

import rego.v1

# ---------------------------------------------------------------------------
# Policy: All managed resources must carry the required tag set
#
# Required tags (must be non-empty strings):
#   - Environment  (e.g. dev | staging | prod)
#   - Team         (owning team)
#   - ManagedBy    (e.g. terraform | terragrunt)
#
# Optional but strongly recommended:
#   - CostCenter
#   - Project
#
# Resources that do not support tags (data sources, IAM policy documents,
# null_resource, etc.) are excluded via _exempt_types.
# ---------------------------------------------------------------------------

_required_tags := {"Environment", "Team", "ManagedBy"}

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
  some required_tag in _required_tags
  not tags[required_tag]
  msg := sprintf(
    "POLICY VIOLATION [required-tags]: resource %q (type: %s) is missing required tag %q",
    [addr, rc.type, required_tag],
  )
}

# Also flag tags that are present but empty
deny contains msg if {
  some addr, rc in input.resource_changes
  not rc.type in _exempt_types
  _is_managed(rc.change.actions)
  tags := object.get(rc.change.after, "tags", {})
  some required_tag in _required_tags
  tags[required_tag] == ""
  msg := sprintf(
    "POLICY VIOLATION [required-tags]: resource %q (type: %s) has empty value for required tag %q",
    [addr, rc.type, required_tag],
  )
}
