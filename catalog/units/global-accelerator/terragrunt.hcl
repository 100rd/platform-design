# ---------------------------------------------------------------------------------------------------------------------
# Global Accelerator — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions an AWS Global Accelerator for multi-region active-active traffic
# distribution. Each regional NLB is registered as an endpoint group.
#
# This is a global resource — in the live tree it should be placed under
# _global/ rather than under a specific region.
#
# Dependencies:
#   - NLB outputs from each region provide endpoint_id (NLB ARN)
#   - S3 bucket for flow log delivery
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/global-accelerator"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------
# In the live tree, the NLB ARNs from each region must be provided via
# dependency blocks or direct inputs. This catalog unit provides the
# structural template; the live terragrunt.hcl will fill in dependencies.
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name    = "${local.environment}-global-accelerator"
  enabled = try(local.account_vars.locals.enable_global_accelerator, false)

  ip_address_type = "IPV4"

  flow_logs_enabled   = true
  flow_logs_s3_bucket = try(local.account_vars.locals.ga_flow_logs_bucket, "")
  flow_logs_s3_prefix = "global-accelerator/"

  listeners = [
    {
      port_ranges = [
        { from = 443, to = 443 },
        { from = 80, to = 80 },
      ]
      protocol        = "TCP"
      client_affinity = "SOURCE_IP"
    },
  ]

  # Endpoint groups must be populated in the live tree with actual NLB ARNs.
  # Example:
  # endpoint_groups = {
  #   eu-west-1 = {
  #     endpoint_id           = dependency.nlb_eu_west_1.outputs.nlb_arn
  #     weight                = 128
  #     health_check_port     = 443
  #     health_check_protocol = "TCP"
  #     health_check_path     = "/healthz"
  #     health_check_interval = 10
  #     threshold_count       = 3
  #     traffic_dial_percentage = 100
  #   }
  #   eu-central-1 = {
  #     endpoint_id           = dependency.nlb_eu_central_1.outputs.nlb_arn
  #     weight                = 128
  #     health_check_port     = 443
  #     health_check_protocol = "TCP"
  #     health_check_path     = "/healthz"
  #     health_check_interval = 10
  #     threshold_count       = 3
  #     traffic_dial_percentage = 100
  #   }
  # }
  endpoint_groups = {}

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
