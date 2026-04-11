package terraform.s3_no_public_access

import rego.v1

# ---------------------------------------------------------------------------
# Policy: No public S3 buckets
#
# Checks both:
#   - aws_s3_bucket_acl with canned ACL set to a public value
#   - aws_s3_bucket_public_access_block missing or disabling all four controls
#
# Violations cause Conftest to exit 1 (deny).
# ---------------------------------------------------------------------------

_public_acls := {"public-read", "public-read-write", "authenticated-read"}

# Deny any S3 bucket ACL resource that uses a canned public ACL
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_s3_bucket_acl"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  rc.change.after.acl in _public_acls
  msg := sprintf(
    "POLICY VIOLATION [s3-no-public-acl]: resource %q sets canned ACL %q — use bucket-level public access block instead",
    [addr, rc.change.after.acl],
  )
}

# Deny any S3 bucket that explicitly disables one of the four public-access block controls
deny contains msg if {
  some addr, rc in input.resource_changes
  rc.type == "aws_s3_bucket_public_access_block"
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  after := rc.change.after

  # Any of the four flags must be true (blocking public access)
  some field in ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]
  after[field] == false

  msg := sprintf(
    "POLICY VIOLATION [s3-public-access-block]: resource %q has %q set to false — all four public access block flags must be true",
    [addr, field],
  )
}
