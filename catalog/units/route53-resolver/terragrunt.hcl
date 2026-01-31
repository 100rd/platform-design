# ---------------------------------------------------------------------------------------------------------------------
# Route53 Resolver — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Creates Route53 Resolver endpoints for cross-account and cross-network DNS resolution.
# Depends on a VPC in the network account for endpoint placement.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/route53-resolver"
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
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-mock-1", "subnet-mock-2"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name       = "${local.account_name}-${local.aws_region}"
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  enable_inbound  = true
  enable_outbound = true

  forwarding_rules = try(local.account_vars.locals.dns_forwarding_rules, {})

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
