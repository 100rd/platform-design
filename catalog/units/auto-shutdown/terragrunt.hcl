# ---------------------------------------------------------------------------------------------------------------------
# Auto-Shutdown — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys EventBridge Scheduler + Lambda to stop dev EC2 instances at 19:00 UTC and
# restart them at 07:30 UTC, Mon-Fri. Only instances tagged AutoShutdown=true are affected.
#
# Deploy in the dev account only. Set enabled = false in staging/prod.
#
# To opt-in an EC2 instance or EKS node group, add tags:
#   Environment = development
#   AutoShutdown = true
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/auto-shutdown"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

inputs = {
  project     = "platform-design"
  environment = local.environment

  # Enable only in dev. This flag should be overridden to false in staging/prod stack configs.
  enabled = local.environment == "dev" ? true : false

  shutdown_schedule = "cron(0 19 ? * MON-FRI *)"
  startup_schedule  = "cron(30 7 ? * MON-FRI *)"
  timezone          = "UTC"

  # Leave empty to skip log encryption in dev (dev KMS key not required)
  kms_key_arn = ""

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    Purpose     = "cost-control"
  }
}
