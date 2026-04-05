# ---------------------------------------------------------------------------------------------------------------------
# VPC Endpoints — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Creates Gateway (S3, DynamoDB) and Interface endpoints for 12 core AWS services.
# Deploy per VPC, per region. Wire VPC and subnet IDs from the vpc catalog unit.
#
# Prerequisites:
#   - vpc catalog unit must be deployed first
#   - A security group allowing HTTPS (443) inbound from the VPC CIDR must exist
#     (typically created by the vpc module or a dedicated sg unit)
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/vpc-endpoints"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
}

dependency "vpc" {
  config_path = find_in_parent_folders("vpc")

  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
  mock_outputs = {
    vpc_id                  = "vpc-00000000000000000"
    private_subnet_ids      = ["subnet-00000000000000001", "subnet-00000000000000002"]
    private_route_table_ids = ["rtb-00000000000000001", "rtb-00000000000000002"]
  }
}

inputs = {
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.private_subnet_ids
  route_table_ids = dependency.vpc.outputs.private_route_table_ids

  # Security group allowing HTTPS inbound from VPC CIDR — create separately or wire from vpc outputs
  security_group_ids = []

  name_prefix = "platform-design-${local.environment}-"

  tags = {
    ManagedBy   = "terragrunt"
    Environment = local.environment
    Region      = local.aws_region
    Purpose     = "vpc-endpoints"
  }
}
