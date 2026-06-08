# ---------------------------------------------------------------------------------------------------------------------
# Remote-Access VPN — Catalog Unit (Network Account)
# ---------------------------------------------------------------------------------------------------------------------
# Deploys the management / remote-access VPN host in the Network account and
# joins it to the hub TGW estate (ADR-0013). The VPN side of the inter-VPC
# access security model; segmentation routes + the prod NACL backstop are wired
# by the sibling `inter-vpc-security` unit.
#
# Reads the VPC + subnets from the `vpc` unit and the EBS/logs KMS key from the
# `kms` unit. Trust sub-pools and the reachable-CIDR allow-list come from
# account.hcl (placeholders / representative ranges — no estate specifics).
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/project/platform-design/terraform/modules/remote-access-vpn"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.account_id
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment

  name = "${local.account_name}-${local.aws_region}"

  # ADR-0013 trust model — representative placeholder ranges (override in account.hcl).
  ravpn = try(local.account_vars.locals.remote_access_vpn, {})
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-mock-priv-1", "subnet-mock-priv-2"]
    public_subnets  = ["subnet-mock-pub-1", "subnet-mock-pub-2"]
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      ebs  = "arn:aws:kms:${local.aws_region}:${local.account_id}:key/00000000-0000-0000-0000-000000000000"
      logs = "arn:aws:kms:${local.aws_region}:${local.account_id}:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  name               = local.name
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnets
  public_subnet_ids  = dependency.vpc.outputs.public_subnets

  # Prefer a dedicated EBS/logs key when present; fall back to the ebs key.
  kms_key_arn = try(dependency.kms.outputs.key_arns["ebs"], dependency.kms.outputs.key_arns["logs"])

  # Trust sub-pools (ADR-0013) — placeholders unless overridden in account.hcl.
  vpn_client_cidr           = try(local.ravpn.vpn_client_cidr, "10.100.0.0/20")
  vpn_ops_subpool_cidr      = try(local.ravpn.vpn_ops_subpool_cidr, "10.100.0.0/24")
  vpn_standard_subpool_cidr = try(local.ravpn.vpn_standard_subpool_cidr, "10.100.1.0/24")

  # Per-CIDR egress allow-list — must agree with the inter-vpc-security TGW routes.
  reachable_cidrs = try(local.ravpn.reachable_cidrs, [])

  # Secrets are set out-of-band; only the secret shells are created here.
  secrets_path_prefix = try(local.ravpn.secrets_path_prefix, "org/network/remote-access-vpn")
  secrets_arn_prefix  = try(local.ravpn.secrets_arn_prefix, "arn:aws:secretsmanager:${local.aws_region}:${local.account_id}:secret:org/network/remote-access-vpn")

  backup_s3_bucket    = try(local.ravpn.backup_s3_bucket, "${local.account_name}-${local.aws_region}-ravpn-backups")
  alert_sns_topic_arn = try(local.ravpn.alert_sns_topic_arn, "arn:aws:sns:${local.aws_region}:${local.account_id}:network-alerts")

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Component   = "remote-access-vpn"
    ADR         = "0013"
  }
}
