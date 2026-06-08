# ---------------------------------------------------------------------------------------------------------------------
# VPC Lattice Resource Connectivity — Network Account, eu-west-1 (ADR-0023)
# ---------------------------------------------------------------------------------------------------------------------
# Identity-scoped, cross-account TCP access to a shared resource (e.g. an RDS DB)
# via a VPC Lattice Resource Gateway + ARN Resource Configuration + Service
# Network + RAM share + IAM auth policy. Bypasses the NLB and, intra-region, the
# Transit Gateway for that flow. Complements ADR-0013 (TGW segmentation).
#
# Epic #252. TCP-only, single-region only.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/vpc-lattice-resource"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# The resource-owning VPC. In live use this is a dependency on the network VPC
# unit (from the connectivity stack); mocked here so plan/validate succeed
# without applied state.
dependency "vpc" {
  config_path = "../connectivity/vpc"

  mock_outputs = {
    vpc_id          = "vpc-0mockmockmock0000"
    private_subnets = ["subnet-mock0a", "subnet-mock0b", "subnet-mock0c"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name = "${local.account_name}-${local.aws_region}-shared-rds"

  # Resource Gateway lives in the resource-owning VPC, spanning its private (multi-AZ) subnets.
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  # Security groups should scope to the resource port (5432/tcp for PostgreSQL).
  # Placeholder — replace with the SG that fronts the shared RDS DB.
  security_group_ids = []

  # Resource Configuration: type = ARN -> the shared RDS DB ARN. Placeholder ARN;
  # replace per shared resource. eu-west-1, single-region (ADR-0023).
  resource_arn  = "arn:aws:rds:eu-west-1:000000000000:db:shared-postgres"
  resource_port = 5432

  # Identity-scoped auth — restrict to our Organization via aws:PrincipalOrgID.
  enable_auth_policy = true
  principal_org_id   = "o-placeholderorg" # TODO: replace with the real AWS Organization ID

  # Cross-account share of the Service Network (org-wide). organization_arn is
  # populated after org creation (see account.hcl).
  enable_ram_share        = true
  share_with_organization = true
  organization_arn        = try(local.account_vars.locals.organization_arn, "")

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "vpc-lattice-resource"
    ADR         = "0023"
  }
}
