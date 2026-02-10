# ---------------------------------------------------------------------------------------------------------------------
# RDS PostgreSQL Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions a PostgreSQL 17 instance in the VPC database subnets with
# encryption at rest (KMS CMK), forced SSL connections, managed master credentials, and
# environment-appropriate HA / backup settings using the terraform-aws-modules/rds/aws module.
#
# PCI-DSS Controls:
#   Req 3.4  — Storage encrypted with KMS CMK (not default aws/rds key)
#   Req 4.1  — SSL enforced via rds.force_ssl=1 parameter group
#   Req 3.6.4 — KMS key auto-rotation (via KMS module dependency)
#
# The RDS security group allows inbound traffic from the EKS cluster security group so that
# platform workloads can reach the database without additional manual rules.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-aws-modules/rds/aws?version=7.1.0"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.account_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: VPC
# ---------------------------------------------------------------------------------------------------------------------

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                     = "vpc-00000000000000000"
    database_subnets           = ["subnet-00000000000000000", "subnet-11111111111111111", "subnet-22222222222222222"]
    database_subnet_group_name = "mock-db-subnet-group"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_security_group_id = "sg-00000000000000000"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: Secrets
# ---------------------------------------------------------------------------------------------------------------------

dependency "secrets" {
  config_path = "../secrets"

  mock_outputs = {
    secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:mock-secret"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: KMS (PCI-DSS Req 3.4 — CMK for RDS storage encryption)
# ---------------------------------------------------------------------------------------------------------------------

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    key_arns = {
      "rds" = "arn:aws:kms:eu-west-1:123456789012:key/mock-rds-key-id"
    }
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  identifier = "${local.environment}-${local.aws_region}-platform-db"

  # Engine
  engine               = "postgres"
  engine_version       = "17.7"
  family               = "postgres17"
  major_engine_version = "17"

  # Instance sizing (defined per environment in account.hcl)
  instance_class    = local.account_vars.locals.rds_instance_class
  allocated_storage = local.account_vars.locals.rds_allocated_storage

  # Database
  db_name  = "platform"
  username = "platform_admin"

  # Let RDS manage the master password via Secrets Manager
  manage_master_user_password = true

  # SSL enforcement — custom parameter group with rds.force_ssl = 1 (PCI-DSS Req 4.1)
  create_db_parameter_group = true
  parameter_group_name      = "${local.environment}-platform-db-pg17-ssl"
  parameters = [
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "pending-reboot"
    }
  ]

  # Networking
  vpc_security_group_ids = [dependency.eks.outputs.cluster_security_group_id]
  db_subnet_group_name   = dependency.vpc.outputs.database_subnet_group_name

  # High availability and durability
  multi_az                = local.account_vars.locals.rds_multi_az
  backup_retention_period = local.environment == "prod" ? 30 : 7
  deletion_protection     = contains(["prod", "staging"], local.environment)

  # Encryption at rest with KMS CMK (PCI-DSS Req 3.4)
  storage_encrypted = true
  kms_key_id        = dependency.kms.outputs.key_arns["rds"]

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Compliance  = "pci-dss"
  }
}
