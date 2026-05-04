# -----------------------------------------------------------------------------
# sso (IAM Identity Center) — variables
# -----------------------------------------------------------------------------

variable "organization_id" {
  description = "AWS Organization ID — used for tagging and as a dependency anchor; the module reads the SSO instance via data source."
  type        = string
}

variable "member_accounts" {
  description = "Map of account short-name -> account metadata. Used by `assignments` to resolve human-readable account names to account IDs."
  type = map(object({
    account_id = string
    email      = string
    ou         = string
  }))
  default = {}
}

variable "permission_sets" {
  description = <<-EOT
    Map of permission-set name -> definition.
    `managed_policies` is a list of AWS-managed policy ARNs (e.g. arn:aws:iam::aws:policy/AdministratorAccess).
    `customer_managed_policies` is a list of customer-managed policy NAMES (the policies must already exist in EVERY target account; SSO references them by name+path).
    `inline_policy_json` is an optional JSON string set as the inline policy (use jsonencode at the call site).
    `permissions_boundary_managed_policy_arn` (optional) attaches a permissions-boundary using an AWS-managed policy.
  EOT
  type = map(object({
    description                             = string
    session_duration                        = string
    managed_policies                        = list(string)
    customer_managed_policies               = optional(list(object({ name = string, path = optional(string, "/") })), [])
    inline_policy_json                      = optional(string, null)
    permissions_boundary_managed_policy_arn = optional(string, null)
  }))
  default = {}
}

variable "groups" {
  description = <<-EOT
    Map of logical key -> Identity Center group display name. The module
    looks each up via `aws_identitystore_group` data sources and stores the
    resolved IDs in the `groups_resolved` output. Logical keys are referenced
    by `assignments`. Group display names must already exist in the IdP
    (provisioned via SCIM or the AWS console). Empty by default for backwards
    compatibility with the pre-#167 callers.
  EOT
  type        = map(string)
  default     = {}
}

variable "assignments" {
  description = <<-EOT
    List of (group, permission_set, account_or_ou) bindings.
    `group_key` references a key in `var.groups`.
    `permission_set` references a key in `var.permission_sets`.
    `target_type` must be either "ACCOUNT" (resolved against `var.member_accounts` by short name) or "AWS_ACCOUNT_ID" (raw 12-digit ID).
    `target_value` is the short-name (when type=ACCOUNT) or the raw ID (when type=AWS_ACCOUNT_ID).
    NOTE: `aws_ssoadmin_account_assignment` does NOT support OUs as targets — OU-level access requires assigning to every member account. The wrapper at the calling stack (terragrunt unit) is responsible for fanning OUs out into account lists if it wants OU-style provisioning.
  EOT
  type = list(object({
    group_key      = string
    permission_set = string
    target_type    = string # "ACCOUNT" or "AWS_ACCOUNT_ID"
    target_value   = string
  }))
  default = []

  validation {
    condition = alltrue([
      for a in var.assignments : contains(["ACCOUNT", "AWS_ACCOUNT_ID"], a.target_type)
    ])
    error_message = "assignments[*].target_type must be one of: ACCOUNT, AWS_ACCOUNT_ID."
  }
}

variable "tags" {
  description = "Tags to apply to permission sets."
  type        = map(string)
  default     = {}
}
