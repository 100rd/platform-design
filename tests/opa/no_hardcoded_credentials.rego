package terraform.no_hardcoded_credentials

import rego.v1

# ---------------------------------------------------------------------------
# Policy: No hardcoded credentials or secrets in Terraform plan output
#
# Checks resource configuration values for patterns that indicate a credential
# or secret has been embedded directly in source code rather than sourced from
# a secrets manager (AWS Secrets Manager, SSM Parameter Store, Vault, etc.).
#
# Patterns checked (case-insensitive attribute names):
#   - password / passwd
#   - secret / secret_key
#   - access_key / aws_access_key_id
#   - token / auth_token / api_token
#   - private_key
#
# Values that indicate the secret is correctly managed (not hardcoded):
#   - Empty string (not yet set / placeholder)
#   - References to Secrets Manager: "arn:aws:secretsmanager:..."
#   - References to SSM Parameter Store: starts with "/aws/reference/secretsmanager/"
#   - Sensitive values redacted by Terraform: "(sensitive value)"
#   - null
# ---------------------------------------------------------------------------

_sensitive_attributes := {
  "password",
  "passwd",
  "secret",
  "secret_key",
  "access_key",
  "aws_access_key_id",
  "aws_secret_access_key",
  "token",
  "auth_token",
  "api_token",
  "api_key",
  "private_key",
  "client_secret",
  "db_password",
  "master_password",
  "user_password",
}

_is_safe_value(v) if v == null
_is_safe_value(v) if v == ""
_is_safe_value(v) if v == "(sensitive value)"
_is_safe_value(v) if startswith(v, "arn:aws:secretsmanager:")
_is_safe_value(v) if startswith(v, "/aws/reference/secretsmanager/")
_is_safe_value(v) if startswith(v, "{{resolve:secretsmanager:")
_is_safe_value(v) if startswith(v, "{{resolve:ssm-secure:")

_looks_like_secret(v) if {
  is_string(v)
  count(v) >= 8
  not _is_safe_value(v)
}

deny contains msg if {
  some addr, rc in input.resource_changes
  actions := rc.change.actions
  not (actions == ["no-op"])
  not (actions == ["read"])
  not (actions == ["delete"])
  after := object.get(rc.change, "after", {})
  some attr_name, attr_val in after
  lower(attr_name) in _sensitive_attributes
  _looks_like_secret(attr_val)
  msg := sprintf(
    "POLICY VIOLATION [no-hardcoded-credentials]: resource %q has a potentially hardcoded value in attribute %q — use AWS Secrets Manager or SSM Parameter Store",
    [addr, attr_name],
  )
}
