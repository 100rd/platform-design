# ---------------------------------------------------------------------------------------------------------------------
# Cilium CNI — Catalog Unit
# ---------------------------------------------------------------------------------------------------------------------
# Deploys Cilium as the CNI for EKS, replacing AWS VPC CNI.
# Must be deployed AFTER EKS but BEFORE Karpenter nodepools.
#
# Prerequisites:
#   - EKS cluster created with cluster_addons.vpc-cni DISABLED
#   - Karpenter EC2NodeClass using Bottlerocket AMI family
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${get_repo_root()}/terraform/modules/cilium"
}

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  environment  = local.account_vars.locals.environment
  aws_region   = local.region_vars.locals.aws_region
  cluster_name = "${local.environment}-${local.aws_region}-platform"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCY: EKS Cluster
# ---------------------------------------------------------------------------------------------------------------------

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint = "https://XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX.gr7.us-east-1.eks.amazonaws.com"
  }

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  cluster_endpoint = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")

  cilium_version = "1.16.5"

  # Start with kube-proxy enabled for safer migration
  # Set to true after validating Cilium is stable
  replace_kube_proxy = local.account_vars.locals.cilium_replace_kube_proxy

  # Hubble observability
  enable_hubble    = true
  enable_hubble_ui = true

  # Prometheus integration
  enable_service_monitor = true

  # ENI prefix delegation for higher pod density
  enable_prefix_delegation = true

  # Bandwidth manager for QoS
  enable_bandwidth_manager = true

  # Default deny policy (enable after migration is complete)
  enable_default_deny = false

  # HA for operator
  operator_replicas = local.environment == "prod" ? 2 : 1
}
