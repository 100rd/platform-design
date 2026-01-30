# ---------------------------------------------------------------------------------------------------------------------
# Monitoring Stack Configuration
# ---------------------------------------------------------------------------------------------------------------------
# This _envcommon file defines the shared monitoring configuration used by all environments.
# It deploys a Prometheus + Grafana observability stack into the EKS cluster using a
# custom Terraform module located in the local modules directory.
#
# The module handles Helm releases, service accounts, and dashboards for platform monitoring.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${dirname(find_in_parent_folders())}/../terraform/modules/monitoring"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region
  environment  = local.env_vars.locals.environment
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "mock-cluster"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "bW9jay1jZXJ0LWRhdGE="
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/MOCK"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_name = dependency.eks.outputs.cluster_name
  environment  = local.environment
  region       = local.aws_region

  # Prometheus
  enable_prometheus = true

  # Grafana
  enable_grafana   = true
  grafana_replicas = local.env_vars.locals.monitoring_replicas

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
