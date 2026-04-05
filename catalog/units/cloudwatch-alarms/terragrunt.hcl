# ---------------------------------------------------------------------------------------------------------------------
# CloudWatch Alarms — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys an SNS topic and CloudWatch alarms for EKS, EC2, ALB, billing, and S3 state.
# Deploy in each workload account. Enable billing alarm in the management account only.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/cloudwatch-alarms"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  account_name = local.account_vars.locals.account_name
  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region

  # Enable billing alarm only in the management account (billing metrics are global/us-east-1)
  org_account_type = try(local.account_vars.locals.org_account_type, "workload")
}

inputs = {
  project     = "platform-design"
  environment = local.environment

  # TODO: Replace with your team's alert email
  alert_email = "platform-team@example.com"

  # KMS encryption for SNS — reference the kms catalog unit output if available
  kms_key_arn = ""

  # Billing alarm: management account only
  enable_billing_alarm  = local.org_account_type == "management" ? true : false
  billing_threshold_usd = 1000

  cpu_threshold_percent    = 80
  memory_threshold_percent = 85

  # Set to ALB ARN suffix when an ALB is present in this environment
  alb_arn_suffix    = ""
  alb_5xx_threshold = 50

  state_bucket_region = local.aws_region

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    Purpose     = "observability"
  }
}
