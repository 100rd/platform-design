# ---------------------------------------------------------------------------------------------------------------------
# RDS PostgreSQL Configuration — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Reusable unit that provisions a PostgreSQL 16 instance in the VPC database subnets with
# encryption at rest, managed master credentials, and environment-appropriate HA / backup
# settings using the terraform-aws-modules/rds/aws registry module.
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
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  identifier = "${local.environment}-${local.aws_region}-platform-db"

  # Engine
  engine         = "postgres"
  engine_version = "17.7"

  # Instance sizing (defined per environment in account.hcl)
  instance_class    = local.account_vars.locals.rds_instance_class
  allocated_storage = local.account_vars.locals.rds_allocated_storage

  # Database
  db_name  = "platform"
  username = "platform_admin"

  # Let RDS manage the master password via Secrets Manager
  manage_master_user_password = true

  # Networking
  vpc_security_group_ids = [dependency.eks.outputs.cluster_security_group_id]
  db_subnet_group_name   = dependency.vpc.outputs.database_subnet_group_name

  # High availability and durability
  multi_az                = local.account_vars.locals.rds_multi_az
  backup_retention_period = local.account_vars.locals.environment == "prod" ? 30 : 7
  deletion_protection     = local.account_vars.locals.environment == "prod" ? true : false

  # Encryption
  storage_encrypted = true

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
