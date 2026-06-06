# ---------------------------------------------------------------------------------------------------------------------
# Break-glass User — Catalog Unit (ADR-0011)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the per-account emergency-access IAM user with destroy protection:
#   - lifecycle { prevent_destroy = true } + force_destroy = false (ADR-0011)
#   - inline MFA-enforcement policy + AdministratorAccess (MFA-present only)
#   - CloudWatch alarm on any break-glass usage (wired to the org CloudTrail log group)
#
# Deploy in every long-lived account (management, network, dev, staging, prod, dr).
# The user name is derived from account.hcl's account_name -> break-glass-<account_name>.
#
# The usage alarm is created only when both cloudtrail_log_group_name and
# alarm_sns_topic_arn are supplied — wire them from the cloudtrail / monitoring
# units in the consuming stack.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/break-glass-user"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
}

inputs = {
  account_name = local.account_name
  name_prefix  = ""

  # Safe by default: the initial access key and console login are opt-in. Set to
  # true on a single bootstrap apply, capture the secret, then revert to false.
  # See variables.tf for the full bootstrap workflow.
  create_access_key    = false
  create_console_login = false

  # Wire these from the cloudtrail + monitoring units to enable the usage alarm.
  # Left empty here so the catalog default is self-contained; override per stack.
  cloudtrail_log_group_name = ""
  alarm_sns_topic_arn       = ""

  tags = {
    ManagedBy  = "terragrunt"
    Compliance = "adr-0011"
  }
}
