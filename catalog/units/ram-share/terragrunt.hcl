# ---------------------------------------------------------------------------------------------------------------------
# RAM Share — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Shares the Transit Gateway with workload accounts via Resource Access Manager.
# Depends on the Transit Gateway being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/ram-share"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

dependency "tgw" {
  config_path = "../transit-gateway"

  mock_outputs = {
    transit_gateway_arn = "arn:aws:ec2:eu-west-1:555555555555:transit-gateway/tgw-mock"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name                    = "${local.account_name}-${local.aws_region}"
  transit_gateway_arn     = dependency.tgw.outputs.transit_gateway_arn
  share_with_organization = true
  organization_arn        = try(local.account_vars.locals.organization_arn, "")

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
