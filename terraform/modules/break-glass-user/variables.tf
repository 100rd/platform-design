# ---------------------------------------------------------------------------------------------------------------------
# Break-glass User Variables
# ---------------------------------------------------------------------------------------------------------------------

variable "account_name" {
  description = "Account short name (e.g. management, prod, security). Used to build the IAM user name break-glass-<account_name>."
  type        = string
}

variable "name_prefix" {
  description = "Optional prefix for the inline-policy and alarm names (e.g. 'platform-'). The IAM user name is always break-glass-<account_name> and is not prefixed."
  type        = string
  default     = ""
}

variable "create_access_key" {
  description = <<-EOT
    Create an initial AWS access key for the break-glass user. Default is false
    (safe by default — the access key is opt-in, set this to true on a single
    apply only when bootstrapping a new break-glass user).

    Bootstrap workflow:
      1. Set to true in the consuming Terragrunt unit
      2. terragrunt apply — creates the user + access key
      3. Capture the secret via: terragrunt output -raw access_key_secret
         (only available once, at creation time)
      4. Move the secret into the team password manager and delete the local file
      5. Remove the resource from state:
         terragrunt state rm 'aws_iam_access_key.this[0]'
      6. Revert this variable to false in the unit so future plans don't create a
         duplicate key (max 2 access keys per IAM user)

    To rotate the key after bootstrap, use 'aws iam create-access-key' and
    'aws iam delete-access-key' directly — Terraform does not track the key after
    the state-rm step.
  EOT
  type        = bool
  default     = false
}

variable "create_console_login" {
  description = <<-EOT
    Create a console login profile for the break-glass user so it can sign in to
    the AWS Console when SSO is unavailable. Default is false (programmatic access
    only). When true, an initial password is generated (sensitive output) and the
    user must reset it on first login.
  EOT
  type        = bool
  default     = false
}

variable "alarm_sns_topic_arn" {
  description = <<-EOT
    SNS topic ARN to notify when the break-glass user authenticates. Leave empty to
    skip the CloudWatch alarm (not recommended for production accounts). The topic
    must exist before this module is applied and must be reachable by CloudWatch
    Logs in this account.
  EOT
  type        = string
  default     = ""
}

variable "cloudtrail_log_group_name" {
  description = <<-EOT
    Name of the CloudWatch Logs group receiving CloudTrail events for this account.
    Required for the break-glass usage alarm. If empty, no metric filter / alarm is
    created and the consumer is responsible for monitoring break-glass use through
    org-wide CloudTrail trails directly.
  EOT
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to taggable resources in this module."
  type        = map(string)
  default     = {}
}
