# ---------------------------------------------------------------------------------------------------------------------
# Karpenter Configuration
# ---------------------------------------------------------------------------------------------------------------------
# This _envcommon file defines the shared Karpenter configuration used by all environments.
# It provisions the Karpenter IAM roles and supporting resources required for just-in-time
# node provisioning using the karpenter sub-module of terraform-aws-modules/eks/aws.
#
# Karpenter replaces the Cluster Autoscaler for dynamic, cost-efficient node scaling.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws//modules/karpenter?version=20.31.0"
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

  # IRSA configuration for Karpenter controller
  irsa_oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  enable_irsa            = true

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}
