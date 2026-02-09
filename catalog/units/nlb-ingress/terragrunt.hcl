# ---------------------------------------------------------------------------------------------------------------------
# NLB Ingress — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Provisions a public-facing Network Load Balancer for EKS ingress traffic.
# TLS termination on port 443 with ACM certificate, forwards to pod IPs.
#
# This NLB serves as the regional endpoint for Global Accelerator in a
# multi-region active-active configuration.
#
# Gated by enable_nlb_ingress in account.hcl.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/nlb-ingress"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
  cluster_name = "${local.environment}-${local.aws_region}-platform"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: VPC — for vpc_id and public subnets
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    public_subnets = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS — ensures cluster exists before NLB is created
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name = "mock-platform"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  name    = "${local.cluster_name}-nlb"
  enabled = try(local.account_vars.locals.enable_nlb_ingress, false)

  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnets

  certificate_arn = try(local.account_vars.locals.nlb_certificate_arn, "")
  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  health_check_protocol = "TCP"
  health_check_port     = "traffic-port"
  health_check_path     = "/healthz"

  deregistration_delay = 30

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
