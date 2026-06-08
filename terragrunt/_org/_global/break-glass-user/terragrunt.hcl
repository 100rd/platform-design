# ---------------------------------------------------------------------------------------------------------------------
# Break-glass User — Management Account (ADR-0011)
# ---------------------------------------------------------------------------------------------------------------------
# Emergency-access IAM user for the management account, used only when SSO /
# Identity Center is unavailable. Carries the ADR-0011 destroy guards
# (prevent_destroy + force_destroy = false) and an MFA-enforced admin policy.
#
# The usage alarm reads from the organization CloudTrail trail's CloudWatch log
# group (the cloudtrail unit in this folder). Provide alarm_sns_topic_arn below
# to enable the alarm — left empty until the security alerting topic exists.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/break-glass-user"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  account_name = local.account_vars.locals.account_name
}

dependency "cloudtrail" {
  config_path = "../cloudtrail"

  mock_outputs = {
    cloudwatch_log_group_name = "/aws/cloudtrail/org-trail-mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  account_name = local.account_name
  name_prefix  = ""

  # Safe by default: the access key and console login are opt-in. Flip to true on
  # a single bootstrap apply, capture the secret, then revert. See variables.tf.
  create_access_key    = false
  create_console_login = false

  # Alarm on any break-glass usage. The log group comes from the org CloudTrail
  # trail. Set alarm_sns_topic_arn to the security alerting topic to enable the
  # CloudWatch alarm chain (metric filter + alarm).
  cloudtrail_log_group_name = dependency.cloudtrail.outputs.cloudwatch_log_group_name
  alarm_sns_topic_arn       = "" # TODO: set to the security SNS topic ARN to enable the usage alarm

  tags = {
    Environment = "management"
    ManagedBy   = "terragrunt"
    Compliance  = "adr-0011"
  }
}
