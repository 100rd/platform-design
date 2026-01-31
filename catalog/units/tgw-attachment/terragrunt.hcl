# ---------------------------------------------------------------------------------------------------------------------
# TGW Attachment — Catalog Unit (Workload Accounts)
# ---------------------------------------------------------------------------------------------------------------------
# Attaches a workload VPC to the Transit Gateway (shared via RAM from network account).
# Gated by enable_tgw_attachment in account.hcl.
# Depends on VPC being created first.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/tgw-attachment"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                 = "vpc-mock"
    private_subnets        = ["subnet-mock-1", "subnet-mock-2", "subnet-mock-3"]
    private_route_table_ids = ["rtb-mock-1"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled            = try(local.account_vars.locals.enable_tgw_attachment, false)
  name               = "${local.environment}-${local.aws_region}-platform"
  transit_gateway_id = try(local.account_vars.locals.transit_gateway_id, "")
  vpc_id             = dependency.vpc.outputs.vpc_id
  subnet_ids         = dependency.vpc.outputs.private_subnets
  route_table_id     = try(local.account_vars.locals.tgw_route_table_id, "")

  vpc_route_table_ids = {
    private = try(dependency.vpc.outputs.private_route_table_ids[0], "")
  }

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
