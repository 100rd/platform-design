# ---------------------------------------------------------------------------------------------------------------------
# Global Accelerator — Live Deployment (Global)
# ---------------------------------------------------------------------------------------------------------------------
# AWS Global Accelerator for active-active multi-region traffic distribution.
# References NLB endpoints from both eu-west-1 and eu-central-1.
#
# This is a global resource — deploy once, routes to all regions.
#
# Usage:
#   terragrunt plan
#   terragrunt apply
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/global-accelerator"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES: NLB from each region
# ---------------------------------------------------------------------------------------------------------------------

dependency "nlb_euw1" {
  config_path = "../../eu-west-1/platform/nlb-ingress"

  mock_outputs = {
    nlb_arn      = "arn:aws:elasticloadbalancing:eu-west-1:222222222222:loadbalancer/net/mock/mock"
    nlb_dns_name = "mock-nlb-euw1.elb.eu-west-1.amazonaws.com"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "nlb_euc1" {
  config_path = "../../eu-central-1/platform/nlb-ingress"

  mock_outputs = {
    nlb_arn      = "arn:aws:elasticloadbalancing:eu-central-1:222222222222:loadbalancer/net/mock/mock"
    nlb_dns_name = "mock-nlb-euc1.elb.eu-central-1.amazonaws.com"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name    = "${local.environment}-global"
  enabled = try(local.account_vars.locals.enable_global_accelerator, false)

  flow_logs_enabled   = true
  flow_logs_s3_bucket = "" # Populate with logging bucket ARN
  flow_logs_s3_prefix = "global-accelerator/"

  listeners = [
    {
      port_ranges     = [{ from = 443, to = 443 }, { from = 80, to = 80 }]
      protocol        = "TCP"
      client_affinity = "SOURCE_IP"
    }
  ]

  endpoint_groups = {
    "eu-west-1" = {
      endpoint_id             = dependency.nlb_euw1.outputs.nlb_arn
      weight                  = 128
      health_check_port       = 443
      health_check_protocol   = "TCP"
      health_check_path       = "/"
      health_check_interval   = 10
      threshold_count         = 3
      traffic_dial_percentage = 100
    }
    "eu-central-1" = {
      endpoint_id             = dependency.nlb_euc1.outputs.nlb_arn
      weight                  = 128
      health_check_port       = 443
      health_check_protocol   = "TCP"
      health_check_path       = "/"
      health_check_interval   = 10
      threshold_count         = 3
      traffic_dial_percentage = 100
    }
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
